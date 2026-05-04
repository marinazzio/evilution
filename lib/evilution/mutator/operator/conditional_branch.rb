# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ConditionalBranch < Evilution::Mutator::Base
  def visit_if_node(node)
    return super unless node.statements

    add_nil_mutation(node.statements, node)
    add_nil_mutation_to_else(node.subsequent, node)

    super
  end

  private

  def add_nil_mutation_to_else(subsequent, node)
    return unless subsequent.is_a?(Prism::ElseNode)
    return if subsequent.statements.nil?

    add_nil_mutation(subsequent.statements, node)
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
