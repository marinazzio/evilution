# frozen_string_literal: true

require_relative "../operator"

# Drop one side of a compound boolean: `a && b` becomes `a` and `b`, and the
# same for `||` (both the symbol and the `and` / `or` keyword forms).
#
# BooleanOperatorReplacement swaps the operator but always keeps both
# operands, so a test that only ever exercises one side of a condition
# survives it. Promoting an operand kills exactly those tests.
class Evilution::Mutator::Operator::BooleanOperandPromotion < Evilution::Mutator::Base
  def visit_and_node(node)
    promote_operands(node)
    super
  end

  def visit_or_node(node)
    promote_operands(node)
    super
  end

  private

  # Nested expressions need no special handling: `a && b && c` is an outer
  # AndNode over an inner one, so the outer visit yields `a && b` and `c`
  # while `super` descends and the inner visit yields `a && c` and `b`.
  def promote_operands(node)
    promote_child(node, node.left)
    promote_child(node, node.right)
  end
end
