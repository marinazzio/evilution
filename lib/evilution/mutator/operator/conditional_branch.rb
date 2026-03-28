# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ConditionalBranch < Evilution::Mutator::Base
  def visit_if_node(node)
    if node.statements && node.subsequent.nil?
      add_mutation(
        offset: node.statements.location.start_offset,
        length: node.statements.location.length,
        replacement: "nil",
        node: node
      )
    elsif node.statements && node.subsequent&.statements
      add_mutation(
        offset: node.statements.location.start_offset,
        length: node.statements.location.length,
        replacement: "nil",
        node: node
      )

      add_mutation(
        offset: node.subsequent.statements.location.start_offset,
        length: node.subsequent.statements.location.length,
        replacement: "nil",
        node: node
      )
    end

    super
  end
end
