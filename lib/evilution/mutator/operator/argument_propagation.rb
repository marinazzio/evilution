# frozen_string_literal: true

require_relative "../operator"

# Replace a call with its only argument: `normalize(value)` becomes `value`.
#
# A survivor means the method's transformation of its input is never
# observed — the tests would pass if the value went through untouched.
# Distinct from method_call_removal, which keeps the receiver instead.
#
# Only identifier-named methods with a single positional argument qualify.
# Operator methods (`a + b`, `a[i]`) are left to binary operand promotion,
# attribute writes to attribute_write_to_read, and a call in void statement
# position to statement_deletion, since there the promoted argument's value
# is discarded anyway.
class Evilution::Mutator::Operator::ArgumentPropagation < Evilution::Mutator::Base
  NON_POSITIONAL = [
    Prism::SplatNode,
    Prism::KeywordHashNode,
    Prism::BlockArgumentNode,
    Prism::ForwardingArgumentsNode
  ].freeze
  private_constant :NON_POSITIONAL

  IDENTIFIER = /\A[[:alpha:]_]/
  private_constant :IDENTIFIER

  def call(subject, **)
    @void_statements = Set.new
    super
  end

  def visit_statements_node(node)
    @void_statements.merge(node.body[...-1])
    super
  end

  def visit_call_node(node)
    promote_child(node, sole_positional_argument(node)) if propagatable?(node)
    super
  end

  private

  def sole_positional_argument(node)
    return unless node.arguments in Prism::ArgumentsNode[arguments: [argument]]

    argument unless NON_POSITIONAL.any? { |type| argument.is_a?(type) }
  end

  def propagatable?(node)
    node.name.match?(IDENTIFIER) && !node.attribute_write? && !@void_statements.include?(node)
  end
end
