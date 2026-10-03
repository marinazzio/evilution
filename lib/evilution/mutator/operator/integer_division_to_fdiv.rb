# frozen_string_literal: true

require_relative "../operator"

# Turn a division into `fdiv`: `a / b` becomes `a.fdiv(b)`.
#
# Between integers `/` drops the remainder while `fdiv` keeps it as a float,
# and for exact types such as Rational or BigDecimal `fdiv` falls back to
# Float. A survivor means no example divides values that leave a remainder,
# or none checks what happens to it.
#
# A float literal on either side is skipped: float division and `fdiv` give
# the same answer, so the mutant would change nothing.
class Evilution::Mutator::Operator::IntegerDivisionToFdiv < Evilution::Mutator::Base
  # Receivers that `.fdiv` can follow directly. Anything else is an operator
  # expression, which `.fdiv` would bind into, so it is grouped first.
  SIMPLE_RECEIVER_TYPES = [
    Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode,
    Prism::GlobalVariableReadNode, Prism::ConstantReadNode, Prism::ConstantPathNode,
    Prism::IntegerNode, Prism::ParenthesesNode, Prism::SelfNode
  ].freeze

  # A method name, as opposed to an operator such as `*` or `-@`.
  METHOD_NAME = /\A[a-zA-Z_]\w*[?!]?\z/

  def visit_call_node(node)
    replace_division(node) if division?(node)
    super
  end

  private

  # The explicit form (`a./(b)`) is left alone: it is rare, and rewriting it
  # gains nothing over the operator form. The operator form always has a
  # receiver and exactly one divisor.
  def division?(node)
    return false unless node.name == :/ && node.call_operator_loc.nil?

    [node.receiver, *node.arguments.arguments].none?(Prism::FloatNode)
  end

  def replace_division(node)
    divisor = node.arguments.arguments.first

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "#{receiver_text(node.receiver)}.fdiv(#{divisor.slice})",
      node: node
    )
  end

  def receiver_text(receiver)
    simple_receiver?(receiver) ? receiver.slice : "(#{receiver.slice})"
  end

  def simple_receiver?(receiver)
    return true if SIMPLE_RECEIVER_TYPES.include?(receiver.class)

    receiver.is_a?(Prism::CallNode) && receiver.name.to_s.match?(METHOD_NAME)
  end
end
