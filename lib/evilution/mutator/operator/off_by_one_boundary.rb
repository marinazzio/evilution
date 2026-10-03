# frozen_string_literal: true

require_relative "../operator"

# Shift a count held in a variable down by one: `n.times` becomes
# `(n - 1).times`, `items.first(n)` becomes `items.first(n - 1)`.
#
# A survivor means no example checks the last iteration or the last element,
# the classic fencepost slip. A literal count is left to IntegerLiteral, which
# already shifts it; this operator reaches the counts that have no literal.
class Evilution::Mutator::Operator::OffByOneBoundary < Evilution::Mutator::Base
  # Methods whose receiver is the count.
  RECEIVER_COUNT_METHODS = %i[times].freeze

  # Methods whose single argument is the count or the bound.
  ARGUMENT_COUNT_METHODS = %i[upto downto take first last drop each_slice each_cons].freeze

  # Arguments that stand in the list without being a value: a splat,
  # keywords, forwarded arguments. Subtracting from them would not parse.
  NON_VALUE_ARGUMENT_TYPES = [
    Prism::SplatNode, Prism::KeywordHashNode, Prism::ForwardingArgumentsNode
  ].freeze

  def visit_call_node(node)
    shift_count(node) unless node.safe_navigation?
    super
  end

  private

  def shift_count(node)
    count = count_of(node)
    return if count.nil? || count.is_a?(Prism::IntegerNode)

    add_mutation(
      offset: count.location.start_offset,
      length: count.location.length,
      replacement: lowered(node, count),
      node: node
    )
  end

  def count_of(node)
    if RECEIVER_COUNT_METHODS.include?(node.name)
      node.receiver if node.arguments.nil?
    elsif ARGUMENT_COUNT_METHODS.include?(node.name)
      single_argument(node)
    end
  end

  def single_argument(node)
    return nil if node.arguments.nil?

    arguments = node.arguments.arguments
    return nil unless arguments.length == 1
    return nil if NON_VALUE_ARGUMENT_TYPES.include?(arguments.first.class)

    arguments.first
  end

  # A receiver is followed by `.method`, so the subtraction is grouped; an
  # argument stands on its own and only needs grouping when it is not a
  # primary expression.
  def lowered(node, count)
    subtraction = "#{receiver_source(count)} - 1"
    count.equal?(node.receiver) ? "(#{subtraction})" : subtraction
  end
end
