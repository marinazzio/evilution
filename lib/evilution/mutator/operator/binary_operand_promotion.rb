# frozen_string_literal: true

require_relative "../operator"

# Replace an arithmetic or bitwise expression with one of its operands:
# `a + b` becomes `a` and `b`.
#
# A survivor means one operand never affects the tested result. Comparisons
# are left to the comparison and conditional operators.
#
# An operand is not promoted when the other side is the operator's integer
# identity — `a + 0` or `a * 1` already equals `a`. A float literal does not
# count (`a + 0.0` turns an Integer into a Float), and neither do shifts,
# since `<<` also appends. A binary send in void statement position is left
# to statement_deletion.
class Evilution::Mutator::Operator::BinaryOperandPromotion < Evilution::Mutator::Base
  OPERATORS = %i[+ - * / % ** & | ^ << >>].to_set.freeze
  private_constant :OPERATORS

  # The literal on the right that makes `left <op> literal` equal `left`.
  RIGHT_IDENTITIES = { :+ => 0, :- => 0, :* => 1, :/ => 1, :** => 1, :| => 0, :^ => 0 }.freeze
  private_constant :RIGHT_IDENTITIES

  # The literal on the left that makes `literal <op> right` equal `right`.
  LEFT_IDENTITIES = { :+ => 0, :* => 1, :| => 0, :^ => 0 }.freeze
  private_constant :LEFT_IDENTITIES

  def call(subject, **)
    @void_statements = Set.new
    super
  end

  def visit_statements_node(node)
    @void_statements.merge(node.body[...-1])
    super
  end

  def visit_call_node(node)
    right = right_operand(node)
    promote_operands(node, node.receiver, right) if right && !@void_statements.include?(node)
    super
  end

  private

  # The single argument of a binary operator send; nil otherwise. An operator
  # send always has a receiver — `+b` without one is the unary `+@`.
  def right_operand(node)
    return unless OPERATORS.include?(node.name)
    return unless node.arguments in Prism::ArgumentsNode[arguments: [right]]

    right
  end

  def promote_operands(node, left, right)
    promote_child(node, left) unless integer_literal?(right, RIGHT_IDENTITIES[node.name])
    promote_child(node, right) unless integer_literal?(left, LEFT_IDENTITIES[node.name])
  end

  def integer_literal?(operand, value)
    operand.is_a?(Prism::IntegerNode) && operand.value == value
  end
end
