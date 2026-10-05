# frozen_string_literal: true

require "prism"

require_relative "../operator"
require_relative "../../ast/value_object_definition"

# Mutate the member list of a value-object definition: `Data.define(:a, :b)`
# and `Struct.new(:a, :b)` lose one member at a time, and have each adjacent
# pair of members swapped.
#
# A surviving drop means no example reads or sets that member. A surviving swap
# means the type is built positionally somewhere the order is never asserted,
# so two members could trade values unnoticed.
#
# Definitions outside any method — assigned to a constant, or the superclass
# of a class — are constant subjects of their own, and this operator mutates
# them there. A constant subject is the definition alone: definitions nested
# in its block are subjects of their own too.
class Evilution::Mutator::Operator::DataStructMember < Evilution::Mutator::Base
  # Arguments whose position and meaning are known: members are symbols, a
  # string is the class name `Struct.new("Name", ...)` takes first, and the
  # keyword hash carries `keyword_init:`. Anything else (a splat, a variable)
  # hides the member list, so the definition is left alone.
  KNOWN_ARGUMENT_TYPES = [Prism::SymbolNode, Prism::StringNode, Prism::KeywordHashNode].freeze

  def self.subject_kinds
    %i[method constant]
  end

  # A constant subject's node is the definition itself, so the visit stops
  # there rather than reaching definitions nested in its block.
  def visit_call_node(node)
    mutate_members(node) if Evilution::AST::ValueObjectDefinition.match?(node)
    super unless @subject.kind == :constant
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
end
