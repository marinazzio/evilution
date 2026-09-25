# frozen_string_literal: true

require_relative "../operator"

# Rewrite a `+` reduction into `sum`: `values.reduce(:+)` becomes
# `values.sum`, `values.inject(10, :+)` becomes `values.sum(10)`, and the
# same for the block-pass form `inject(&:+)`.
#
# The two differ on an empty collection (nil vs 0), on non-numeric elements
# (`reduce` concatenates strings and arrays, `sum` raises TypeError without a
# matching initial value) and on float precision (`sum` compensates rounding
# error). A survivor means none of those edges is tested.
class Evilution::Mutator::Operator::ReduceToSum < Evilution::Mutator::Base
  SELECTORS = %i[reduce inject].freeze
  private_constant :SELECTORS

  NON_VALUE_ARGUMENTS = [Prism::SplatNode, Prism::KeywordHashNode].freeze
  private_constant :NON_VALUE_ARGUMENTS

  def visit_call_node(node)
    rewrite(node) if node.receiver && SELECTORS.include?(node.name)
    super
  end

  private

  def rewrite(node)
    initial = initial_arguments(node)
    return unless initial && initial.length <= 1
    return if initial.any? { |argument| NON_VALUE_ARGUMENTS.any? { |type| argument.is_a?(type) } }

    # A literal block never reaches here, so the call ends at its argument
    # list or block-pass: cut from the selector to the end of the call.
    start = node.message_loc.start_offset
    replacement = initial.empty? ? "sum" : "sum(#{source_of(initial.first)})"
    add_mutation(offset: start, length: node.end_offset - start, replacement: replacement, node: node)
  end

  # The arguments besides the `+` operand — at most an initial value — when
  # the call is a `+` reduction; nil otherwise.
  def initial_arguments(node)
    arguments = node.arguments ? node.arguments.arguments : []

    if plus_block_pass?(node.block)
      arguments unless plus_symbol?(arguments.last)
    elsif node.block.nil? && plus_symbol?(arguments.last)
      arguments[...-1]
    end
  end

  def plus_block_pass?(block)
    block.is_a?(Prism::BlockArgumentNode) && plus_symbol?(block.expression)
  end

  def plus_symbol?(node)
    node.is_a?(Prism::SymbolNode) && node.unescaped == "+"
  end
end
