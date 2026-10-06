# frozen_string_literal: true

require "prism"
require_relative "version"
require_relative "spec_ast_cache"
require_relative "ast/value_object_definition"
require_relative "ast/scope_declaration"
require_relative "ast/aasm_declaration"

class Evilution::ExampleFilter
  VALID_FALLBACKS = %i[full_file unresolved].freeze
  private_constant :VALID_FALLBACKS

  def initialize(cache:, fallback: :full_file, source_cache: nil)
    raise ArgumentError, "invalid fallback: #{fallback.inspect}" unless VALID_FALLBACKS.include?(fallback)

    @cache = cache
    @fallback = fallback
    @source_cache = source_cache
  end

  def call(mutation, spec_paths)
    return fallback_result(spec_paths) if spec_paths.nil? || spec_paths.empty?

    token = extract_token(mutation)
    return fallback_result(spec_paths) unless token

    locations = scan_specs(token, spec_paths)
    return fallback_result(spec_paths) if locations.empty?

    locations.sort
  end

  private

  def fallback_result(spec_paths)
    case @fallback
    when :full_file then spec_paths
    when :unresolved then nil
    end
  end

  def extract_token(mutation)
    result = if @source_cache.nil?
               Prism.parse(mutation.original_source)
             else
               @source_cache.fetch(mutation.original_source)
             end
    return nil if result.failure?

    finder = EnclosingNodeFinder.new(mutation.line)
    finder.visit(result.value)
    finder.token
  end

  def scan_specs(token, spec_paths)
    pattern = /(?<!\w)#{Regexp.escape(token.downcase)}(?!\w)/
    locations = []
    spec_paths.each do |path|
      blocks = @cache.fetch(path)
      matches = blocks.select { |b| pattern.match?(b.body_text) }
      innermost = filter_innermost(matches)
      innermost.each { |b| locations << "#{path}:#{b.line}" }
    end
    locations.uniq
  end

  def filter_innermost(matches)
    matches.reject do |outer|
      matches.any? do |inner|
        next false if inner.equal?(outer)

        contained?(inner, outer)
      end
    end
  end

  def contained?(inner, outer)
    inner.line >= outer.line && inner.end_line <= outer.end_line &&
      !(inner.line == outer.line && inner.end_line == outer.end_line)
  end

  class EnclosingNodeFinder < Prism::Visitor
    attr_reader :token

    def initialize(target_line)
      @target_line = target_line
      @def_stack = []
      @class_stack = []
      @token = nil
      @found = false
      super()
    end

    def visit_def_node(node)
      return if @found
      return unless target_within?(node)

      @def_stack.push(node.name.to_s)
      capture_if_match(node)
      super
      @def_stack.pop
    end

    def visit_class_node(node)
      return if @found
      return unless target_within?(node)

      @class_stack.push(unqualified_name(node.constant_path))
      capture_if_match(node)
      super
      @class_stack.pop
    end

    def visit_module_node(node)
      return if @found
      return unless target_within?(node)

      @class_stack.push(unqualified_name(node.constant_path))
      capture_if_match(node)
      super
      @class_stack.pop
    end

    # A value-object definition assigned to a constant names the type its
    # specs build (`Point = Data.define(:x, :y)` -> `Point`), like a class.
    def visit_constant_write_node(node)
      within_value_object(node, node.name.to_s) { super }
    end

    def visit_constant_path_write_node(node)
      within_value_object(node, node.target.name.to_s) { super }
    end

    # A scope declaration names the class method its specs call
    # (`scope :for_owner, -> { }` -> `for_owner`), like a def; nothing inside
    # its body names anything closer.
    #
    # An aasm event or state names the methods its specs call (`event :ship`
    # -> `ship!`, `state :paid` -> `paid?`), which share its name as a word.
    def visit_call_node(node)
      return super unless target_within?(node)

      token = declaration_token(node)
      return super unless token

      @token = token
    end

    private

    def declaration_token(node)
      if Evilution::AST::ScopeDeclaration.body_of(node)
        Evilution::AST::ScopeDeclaration.scope_name(node)
      else
        Evilution::AST::AasmDeclaration.token_at(node, @target_line)
      end
    end

    def within_value_object(node, name)
      return yield unless Evilution::AST::ValueObjectDefinition.match?(node.value)

      @class_stack.push(name)
      capture_if_match(node)
      yield
      @class_stack.pop
    end

    def capture_if_match(node)
      return if @found
      return unless target_within?(node)

      @token = @def_stack.last || @class_stack.last
      @found = true if @def_stack.any?
    end

    def target_within?(node)
      loc = node.location
      @target_line.between?(loc.start_line, loc.end_line)
    end

    def unqualified_name(constant_path)
      raw = constant_path.respond_to?(:name) ? constant_path.name.to_s : constant_path.to_s
      raw.split("::").last
    end
  end
  private_constant :EnclosingNodeFinder
end
