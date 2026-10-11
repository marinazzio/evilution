# frozen_string_literal: true

require_relative "../operator"

# Retarget an operator write on an attribute at the instance variable it
# goes through: `@account.balance += amount` becomes `@account += amount`.
#
# The value is still computed and still assigned, only to the wrong place:
# the object's attribute is left as it was and the variable is replaced. A
# survivor means the tests exercise the line without ever looking at what it
# was meant to change. Where the object does not answer the operator the
# mutant raises NoMethodError, which any test reaching the line kills.
#
# Only a receiver that is an instance variable qualifies. `self` cannot be
# assigned to, and behind a longer receiver (`@user.account.balance += x`)
# sits another attribute, not a variable.
class Evilution::Mutator::Operator::OperatorWriteReceiverPromotion < Evilution::Mutator::Base
  def visit_call_operator_write_node(node)
    promote_receiver(node) if node.receiver.is_a?(Prism::InstanceVariableReadNode)
    super
  end

  private

  # Replaces `@account.balance`, up to the end of the attribute's name, with
  # `@account`. What is left is an operator write on a variable, which always
  # parses.
  def promote_receiver(node)
    offset = node.start_offset

    add_mutation(
      offset: offset,
      length: node.message_loc.end_offset - offset,
      replacement: source_of(node.receiver),
      node: node
    )
  end
end
