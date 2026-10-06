# frozen_string_literal: true

require "prism"
require_relative "../ast"
require_relative "value_object_definition"
require_relative "scope_declaration"
require_relative "aasm_declaration"
require_relative "included_block"
require_relative "callback_declaration"

module Evilution::AST
  class Parser
    def call(file_path)
      raise Evilution::ParseError.new("file not found: #{file_path}", file: file_path) unless File.exist?(file_path)

      begin
        source = File.read(file_path)
      rescue SystemCallError => e
        raise Evilution::ParseError.new("cannot read #{file_path}: #{e.message}", file: file_path)
      end
      result = Prism.parse(source)

      if result.failure?
        raise Evilution::ParseError.new("failed to parse #{file_path}: #{result.errors.map(&:message).join(", ")}",
                                        file: file_path)
      end

      extract_subjects(result.value, source, file_path)
    end

    private

    def extract_subjects(tree, source, file_path)
      finder = SubjectFinder.new(source, file_path)
      finder.visit(tree)
      finder.subjects
    end
  end

  class SubjectFinder < Prism::Visitor
    attr_reader :subjects

    def initialize(source, file_path)
      @source = source
      @file_path = file_path
      @subjects = []
      @context = []
      @singleton = [false]
    end

    def visit_module_node(node)
      @context.push(constant_name(node.constant_path))
      IncludedBlock.in_body(node.body).each do |block|
        add_scope_subjects(block.body)
        add_aasm_subjects(block.body)
      end
      within_scope(singleton: false) { super }
      @context.pop
    end

    # A class whose superclass is a value-object definition
    # (`class Coord < Data.define(:lat, :lng)`) makes a constant subject of
    # that definition, named after the class.
    def visit_class_node(node)
      @context.push(constant_name(node.constant_path))
      superclass = node.superclass
      add_subject(superclass, @context.join("::"), :constant) if ValueObjectDefinition.match?(superclass)
      add_scope_subjects(node.body)
      add_aasm_subjects(node.body)
      add_callback_subjects(node.body)
      within_scope(singleton: false) { super }
      @context.pop
    end

    # A `def` inside `class << self` defines a method on the enclosing
    # class's singleton, like `def self.name`; inside `class << Store` it
    # defines one on Store.
    def visit_singleton_class_node(node)
      constant = constant_expression?(node.expression)
      @context.push(constant_name(node.expression)) if constant
      within_scope(singleton: true) { super }
      @context.pop if constant
    end

    def visit_def_node(node)
      separator = node.receiver || @singleton.last ? "." : "#"
      add_subject(node, "#{@context.join("::")}#{separator}#{node.name}", :method)
      super
    end

    def visit_constant_write_node(node)
      return super unless ValueObjectDefinition.match?(node.value)

      within_definition(node.value, node.name.to_s) { super }
    end

    def visit_constant_path_write_node(node)
      return super unless ValueObjectDefinition.match?(node.value)

      within_definition(node.value, path_name(node.target)) { super }
    end

    private

    def within_scope(singleton:)
      @singleton.push(singleton)
      yield
    ensure
      @singleton.pop
    end

    def constant_expression?(node)
      node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
    end

    # A value-object definition assigned to a constant is a subject of its
    # own, and a scope for what its block defines: `def area` in
    # `Size = Struct.new(:w, :h) do ... end` is `Size#area`.
    def within_definition(definition, name)
      @context.push(name)
      add_subject(definition, @context.join("::"), :constant)
      yield
      @context.pop
    end

    # `scope :recent, -> { ... }` defines the class method `recent`. The
    # subject spans the whole declaration and mutates its body.
    # Written in a concern's `included` block it defines that method on every
    # class including the concern, and is named after the concern.
    def add_scope_subjects(body)
      ScopeDeclaration.in_body(body).each do |declaration|
        name = "#{@context.join("::")}.#{ScopeDeclaration.scope_name(declaration)}"
        add_subject(ScopeDeclaration.body_of(declaration), name, :scope, span: declaration)
      end
    end

    # A guard or callback written out inside `aasm do ... end` runs when the
    # method its event or state defines is called (`ship`, `paid?`), and is
    # named after it. The subject spans that declaration and mutates the
    # callable's body; one event may hold several. A machine declared in a
    # concern's `included` block is named after the concern.
    def add_aasm_subjects(body)
      AasmDeclaration.in_body(body).each do |callable|
        name = "#{@context.join("::")}##{callable.method_name}"
        add_subject(callable.body, name, :aasm, span: callable.declaration)
      end
    end

    # A condition or a callback written out in a declaration such as
    # `validate :credit_limit, if: -> { ... }` defines no method to be named
    # after, so it is named the way the declaration reads:
    # `Order.validate(:credit_limit)`. The subject spans the declaration and
    # mutates the callable's body.
    def add_callback_subjects(body)
      CallbackDeclaration.in_body(body).each do |callable|
        add_subject(callable.body, "#{@context.join("::")}.#{callable.label}", :callback, span: callable.declaration)
      end
    end

    def add_subject(node, name, kind, span: node)
      loc = span.location
      source = @source.byteslice(loc.start_offset, loc.end_offset - loc.start_offset)
                      .force_encoding(@source.encoding)

      @subjects << Evilution::Subject.new(
        name: name,
        file_path: @file_path,
        line_number: loc.start_line,
        source: source,
        node: node,
        kind: kind
      )
    end

    # `self::Unit` has no static full name; it is named within the scope it
    # is written in, like a plain `Unit`.
    def path_name(target)
      target.full_name.delete_prefix("::")
    rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
      target.name.to_s
    end

    # `class self::Unit` and `class << self::Unit` have no static full name
    # either; like `path_name`, they are named by their own constant.
    def constant_name(node)
      if node.respond_to?(:full_name)
        node.full_name
      else
        node.name.to_s
      end
    rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
      node.name.to_s
    end
  end
end
