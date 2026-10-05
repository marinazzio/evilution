# frozen_string_literal: true

require "prism"
require_relative "../ast"
require_relative "value_object_definition"

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
    end

    def visit_module_node(node)
      @context.push(constant_name(node.constant_path))
      super
      @context.pop
    end

    # A class whose superclass is a value-object definition
    # (`class Coord < Data.define(:lat, :lng)`) makes a constant subject of
    # that definition, named after the class.
    def visit_class_node(node)
      @context.push(constant_name(node.constant_path))
      superclass = node.superclass
      add_subject(superclass, @context.join("::"), :constant) if ValueObjectDefinition.match?(superclass)
      super
      @context.pop
    end

    def visit_def_node(node)
      separator = node.receiver ? "." : "#"
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

    # A value-object definition assigned to a constant is a subject of its
    # own, and a scope for what its block defines: `def area` in
    # `Size = Struct.new(:w, :h) do ... end` is `Size#area`.
    def within_definition(definition, name)
      @context.push(name)
      add_subject(definition, @context.join("::"), :constant)
      yield
      @context.pop
    end

    def add_subject(node, name, kind)
      loc = node.location
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

    def constant_name(node)
      if node.respond_to?(:full_name)
        node.full_name
      else
        node.name.to_s
      end
    end
  end
end
