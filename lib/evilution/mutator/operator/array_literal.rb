# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ArrayLiteral < Evilution::Mutator::Base
  def visit_array_node(node)
    if node.opening_loc && node.elements.any?
      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "[]",
        node: node
      )

      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "nil",
        node: node
      )
    end

    super
  end
end
