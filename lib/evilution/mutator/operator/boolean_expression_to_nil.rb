# frozen_string_literal: true

require_relative "../operator"

# Replace a whole compound boolean with `nil`: `a && b` becomes `nil`, and
# the same for `||` and the `and` / `or` keyword forms.
#
# Where BooleanOperandPromotion drops one side, this drops both. The
# survivor it targets is a condition whose value is never asserted — code
# that runs the expression for its side effects, or a test that only checks
# the branch was taken rather than what the branch was given.
class Evilution::Mutator::Operator::BooleanExpressionToNil < Evilution::Mutator::Base
  def visit_and_node(node)
    mutate_to_nil(node)
    super
  end

  def visit_or_node(node)
    mutate_to_nil(node)
    super
  end
end
