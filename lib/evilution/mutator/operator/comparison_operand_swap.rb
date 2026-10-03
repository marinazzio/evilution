# frozen_string_literal: true

require_relative "../operator"

# Swap the operands of a spaceship comparison: `a <=> b` becomes `b <=> a`.
#
# The result changes sign, so a sort block sorts the other way and a custom
# `<=>` orders the other way round. A survivor means no example asserts the
# direction of the ordering.
#
# Two-argument ordering methods (`between?`, `clamp`) are reversed by
# ArgumentOrderPermutation. Identical operands are not swapped, since that
# would reproduce the original comparison, and neither is a safe-navigation
# call, where moving the other operand into the receiver's place changes what
# may be nil.
class Evilution::Mutator::Operator::ComparisonOperandSwap < Evilution::Mutator::Base
  def visit_call_node(node)
    swap_operands(node) if spaceship?(node)
    super
  end

  private

  # Ruby has no receiverless spaceship, but the explicit form can be written
  # with no argument or several (`a.<=>`, `a.<=>(b, c)`); those have no pair
  # of operands to swap.
  def spaceship?(node)
    return false unless node.name == :<=> && !node.safe_navigation?
    return false if node.arguments.nil?

    node.arguments.arguments.length == 1
  end

  # Whatever sits between the operands — the operator and its spacing, or
  # `.<=>(` in the explicit form — stays in place.
  def swap_operands(node)
    left = node.receiver
    right = node.arguments.arguments.first
    return if left.slice == right.slice

    start_offset = left.location.start_offset

    add_mutation(
      offset: start_offset,
      length: right.location.end_offset - start_offset,
      replacement: "#{right.slice}#{source_between(left, right)}#{left.slice}",
      node: node
    )
  end

  def source_between(left, right)
    byteslice_source(left.location.end_offset, right.location.start_offset - left.location.end_offset)
  end
end
