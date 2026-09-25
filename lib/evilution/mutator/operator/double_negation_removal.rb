# frozen_string_literal: true

require_relative "../operator"

# Replace a double negation with its operand: `!!value` becomes `value`, and
# the same for the `not not value` keyword form.
#
# A survivor means no test distinguishes a truthy object from `true` (or nil
# from `false`) — the boolean coercion is never observed.
class Evilution::Mutator::Operator::DoubleNegationRemoval < Evilution::Mutator::Base
  def visit_call_node(node)
    inner = node.receiver
    promote_child(node, inner.receiver) if negation?(node) && negation?(inner)
    super
  end

  private

  def negation?(node)
    node.is_a?(Prism::CallNode) && node.name == :!
  end
end
