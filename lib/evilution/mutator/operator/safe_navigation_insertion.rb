# frozen_string_literal: true

require_relative "../operator"
require_relative "safe_navigation_removal"

# Replace a plain call with safe navigation: `user.name` becomes
# `user&.name`, and the same for the `||=`, `&&=` and operator-write forms.
#
# The mutant only differs when the receiver is nil, where it returns nil
# instead of raising NoMethodError. A survivor means no test reaches the call
# with a nil receiver and expects the error.
#
# It touches nearly every call and survives wherever the receiver is never
# nil, so it is registered for the strict profile only. Receivers that can
# never be nil (`self`, literals, constants) are skipped, since the mutant is
# equivalent there.
class Evilution::Mutator::Operator::SafeNavigationInsertion < Evilution::Mutator::Base
  NEVER_NIL_RECEIVERS = [
    *Evilution::Mutator::Operator::SafeNavigationRemoval::NEVER_NIL_RECEIVERS,
    Prism::ConstantReadNode,
    Prism::ConstantPathNode
  ].freeze
  private_constant :NEVER_NIL_RECEIVERS

  def visit_call_node(node)
    mutate_plain_call(node)
    super
  end

  def visit_call_or_write_node(node)
    mutate_plain_call(node)
    super
  end

  def visit_call_and_write_node(node)
    mutate_plain_call(node)
    super
  end

  def visit_call_operator_write_node(node)
    mutate_plain_call(node)
    super
  end

  private

  def mutate_plain_call(node)
    operator = node.call_operator_loc
    return unless operator && operator.slice == "."
    return if NEVER_NIL_RECEIVERS.any? { |type| node.receiver.is_a?(type) }

    add_mutation(offset: operator.start_offset, length: operator.length, replacement: "&.", node: node)
  end
end
