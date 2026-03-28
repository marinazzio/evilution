# frozen_string_literal: true

class Evilution::Mutator::Operator::NegationInsertion < Evilution::Mutator::Base
  def visit_call_node(node)
    if node.name.to_s.end_with?("?")
      add_mutation(
        offset: node.location.start_offset,
        length: 0,
        replacement: "!",
        node: node
      )
    end

    super
  end
end
