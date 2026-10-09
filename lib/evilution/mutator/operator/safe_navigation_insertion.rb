# frozen_string_literal: true

require_relative "../operator"
require_relative "../../ast/never_nil"

# Replace a plain call with safe navigation: `user.name` becomes
# `user&.name`, and the same for the `||=`, `&&=` and operator-write forms.
#
# The mutant only differs when the receiver is nil: the call is then skipped
# and the expression is nil, where the plain call raises NoMethodError or
# runs a method nil has (`nil.to_a` is `[]`). A survivor means no test
# reaches the call with a nil receiver and checks what comes of it.
#
# It touches nearly every call and survives wherever the receiver is never
# nil, so it is registered for the strict profile only. Receivers that can
# never be nil (`self`, literals other than `nil`, constants) are skipped,
# since the mutant is equivalent there.
class Evilution::Mutator::Operator::SafeNavigationInsertion < Evilution::Mutator::Base
  # A constant could hold nil, but one that receives a call does not in
  # practice.
  CONSTANTS = [Prism::ConstantReadNode, Prism::ConstantPathNode].freeze
  private_constant :CONSTANTS

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
    return if never_nil?(node.receiver)

    add_mutation(offset: operator.start_offset, length: operator.length, replacement: "&.", node: node)
  end

  def never_nil?(receiver)
    Evilution::AST::NeverNil.node?(receiver) || CONSTANTS.include?(receiver.class)
  end
end
