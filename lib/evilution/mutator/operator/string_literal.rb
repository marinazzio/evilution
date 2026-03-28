# frozen_string_literal: true

class Evilution::Mutator::Operator::StringLiteral < Evilution::Mutator::Base
  def visit_string_node(node)
    replacement = node.content.empty? ? '"mutation"' : '""'

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: replacement,
      node: node
    )

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "nil",
      node: node
    )

    super
  end
end
