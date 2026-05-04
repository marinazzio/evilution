# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ConditionalBranch < Evilution::Mutator::Base
  def visit_if_node(node)
    return super unless node.statements
    return super if node.subsequent && node.subsequent.statements.nil?

    add_nil_mutation(node.statements, node)
    add_nil_mutation(node.subsequent.statements, node) if node.subsequent

    super
  end

  private

  def add_nil_mutation(statements, node)
    add_mutation(
      offset: statements.location.start_offset,
      length: statements.location.length,
      replacement: "nil",
      node: node
    )
  end
end
