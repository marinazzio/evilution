# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ReturnValueRemoval < Evilution::Mutator::Base
  def visit_return_node(node)
    if node.arguments
      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "return",
        node: node
      )
    end

    super
  end
end
