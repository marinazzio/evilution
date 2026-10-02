# frozen_string_literal: true

require "prism"

require_relative "../operator"

# Mutate the member list of a value-object definition: `Data.define(:a, :b)`
# and `Struct.new(:a, :b)` lose one member at a time, and have each adjacent
# pair of members swapped.
#
# A surviving drop means no example reads or sets that member. A surviving swap
# means the type is built positionally somewhere the order is never asserted,
# so two members could trade values unnoticed.
#
# Most definitions sit in a class body rather than in a method, where no
# subject reaches them. Those are attributed to the first method of the
# enclosing class or module, the way MixinRemoval and SuperclassRemoval
# attribute theirs.
class Evilution::Mutator::Operator::DataStructMember < Evilution::Mutator::Base
  DEFINERS = { Data: :define, Struct: :new }.freeze

  # Arguments whose position and meaning are known: members are symbols, a
  # string is the class name `Struct.new("Name", ...)` takes first, and the
  # keyword hash carries `keyword_init:`. Anything else (a splat, a variable)
  # hides the member list, so the definition is left alone.
  KNOWN_ARGUMENT_TYPES = [Prism::SymbolNode, Prism::StringNode, Prism::KeywordHashNode].freeze

  def self.definition?(node)
    receiver = node.receiver
    return false unless bare_constant?(receiver)

    DEFINERS[receiver.name] == node.name
  end

  def self.bare_constant?(node)
    return true if node.is_a?(Prism::ConstantReadNode)

    node.is_a?(Prism::ConstantPathNode) && node.parent.nil?
  end

  def call(subject, filter: nil)
    super
    class_level_definitions(subject).each { |node| mutate_members(node) }
    @mutations
  end

  def visit_call_node(node)
    mutate_members(node) if self.class.definition?(node)
    super
  end

  private

  def mutate_members(node)
    arguments = node.arguments ? node.arguments.arguments : []
    members = member_indexes(arguments)
    # A lone member has no neighbour to swap with, and dropping it would leave
    # `Struct.new()`, which raises on Rubies that require at least one member.
    return if members.length < 2

    slices = arguments.map(&:slice)
    members.each { |index| emit_member_drop(node, slices, index) }
    members.each_cons(2) { |left, right| emit_member_swap(node, slices, left, right) }
  end

  def member_indexes(arguments)
    return [] unless arguments.all? { |argument| KNOWN_ARGUMENT_TYPES.include?(argument.class) }

    arguments.each_index.select { |index| arguments[index].is_a?(Prism::SymbolNode) }
  end

  def emit_member_drop(node, slices, index)
    remaining = slices.dup
    remaining.delete_at(index)
    replace_arguments(node, remaining)
  end

  def emit_member_swap(node, slices, left, right)
    return if slices[left] == slices[right]

    swapped = slices.dup
    swapped[left], swapped[right] = swapped[right], swapped[left]
    replace_arguments(node, swapped)
  end

  def replace_arguments(node, slices)
    location = node.arguments.location

    add_mutation(
      offset: location.start_offset,
      length: location.length,
      replacement: slices.join(", "),
      node: node
    )
  end

  def class_level_definitions(subject)
    tree = self.class.parsed_tree_for(subject.file_path, @file_source)
    collector = DefinitionCollector.new
    collector.visit(tree)

    collector.definitions.filter_map do |node, scope|
      node if first_method_line(scope) == subject.line_number
    end
  end

  def first_method_line(scope)
    finder = FirstMethodFinder.new
    scope.compact_child_nodes.each { |child| finder.visit(child) }
    finder.line
  end

  # Collects the definitions that sit outside every method, each paired with
  # the scope whose first method stands in as its subject: the innermost
  # enclosing class or module, or, at the top level, the definition's own
  # block. A top-level definition without a block has no such scope and is
  # not collected; borrowing an unrelated method would run its mutants against
  # tests that never load it.
  class DefinitionCollector < Prism::Visitor
    attr_reader :definitions

    def initialize
      super
      @definitions = []
      @scopes = []
    end

    def visit_class_node(node)
      within(node) { super }
    end

    def visit_module_node(node)
      within(node) { super }
    end

    # Definitions inside a method are reached through that method's own
    # subject by the operator's visitor.
    def visit_def_node(_node); end

    def visit_call_node(node)
      if Evilution::Mutator::Operator::DataStructMember.definition?(node)
        scope = @scopes.last || node.block
        @definitions << [node, scope] if scope
      end

      super
    end

    private

    def within(scope)
      @scopes.push(scope)
      yield
    ensure
      @scopes.pop
    end
  end

  # Finds the line of the first method written in a scope, in source order.
  # Nested classes and modules are not searched: their methods are subjects of
  # that inner scope, not of the one the definition is written in.
  class FirstMethodFinder < Prism::Visitor
    attr_reader :line

    def visit_class_node(_node); end

    def visit_module_node(_node); end

    def visit_def_node(node)
      @line = node.location.start_line if @line.nil?
    end
  end
end
