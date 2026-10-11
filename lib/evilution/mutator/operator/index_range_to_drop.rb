# frozen_string_literal: true

require_relative "../operator"

# Take the tail of a list with `drop` instead of a range index:
# `list[n..-1]` and the endless `list[n..]` / `list[n...]` become
# `list.drop(n)`.
#
# The two differ only past the end: a start beyond the last element gives
# `nil` from the index and an empty array from `drop`. A survivor means no
# test reaches that boundary.
#
# A literal start of zero is skipped, never being out of range, and so is a
# negative literal, which `drop` rejects with ArgumentError. A range that
# stops short of the last element (`n...-1`, `n..-2`) is no tail at all. A
# read in void statement position is left to statement_deletion, and index
# writes are another method altogether.
#
# The receiver's type is unknown here: on a String the mutant raises
# NoMethodError, which any test reaching the line kills.
class Evilution::Mutator::Operator::IndexRangeToDrop < Evilution::Mutator::Base
  LAST_INDEX = -1
  private_constant :LAST_INDEX

  def call(subject, **)
    @void_statements = Set.new
    super
  end

  def visit_statements_node(node)
    @void_statements.merge(node.body[...-1])
    super
  end

  def visit_call_node(node)
    start = tail_start(node)
    replace_span(node: node, target: node, replacement: drop_call(node, start)) if start
    super
  end

  private

  # Where the tail begins, when `node` reads from there to the last element.
  # A beginless range has no start to hand to `drop`, and answers nil too.
  def tail_start(node)
    return unless node.name == :[] && !@void_statements.include?(node)
    return unless node.arguments in Prism::ArgumentsNode[arguments: [Prism::RangeNode => range]]

    range.left if to_the_end?(range) && droppable_start?(range.left)
  end

  def to_the_end?(range)
    stop = range.right
    return true if stop.nil?

    !range.exclude_end? && stop.is_a?(Prism::IntegerNode) && stop.value == LAST_INDEX
  end

  def droppable_start?(start)
    !start.is_a?(Prism::IntegerNode) || start.value.positive?
  end

  def drop_call(node, start)
    operator = node.safe_navigation? ? "&." : "."
    "#{source_of(node.receiver)}#{operator}drop(#{source_of(start)})"
  end
end
