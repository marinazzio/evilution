# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ConditionalBranch < Evilution::Mutator::Base
  def visit_if_node(node)
    blank_branches(node, node.subsequent)

    super
  end

  # Prism gives `unless` its own node type, and names the else slot
  # `else_clause` rather than IfNode's `subsequent`. Everything below that is
  # the same shape, so both forms share the branch handling.
  def visit_unless_node(node)
    blank_branches(node, node.else_clause)

    super
  end

  private

  def blank_branches(node, else_clause)
    return if node.statements.nil?

    add_nil_mutation(node.statements, node)
    add_nil_mutation_to_else(else_clause, node)
  end

  def add_nil_mutation_to_else(else_clause, node)
    return unless else_clause.is_a?(Prism::ElseNode)
    return if else_clause.statements.nil?

    add_nil_mutation(else_clause.statements, node)
  end

  def add_nil_mutation(statements, node)
    add_mutation(
      offset: statements.location.start_offset,
      length: statements.location.length,
      replacement: "nil",
      node: node
    )
  end
end
