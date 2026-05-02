# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::PredicateToNil < Evilution::Mutator::Base
  def visit_call_node(node)
    if node.name.to_s.end_with?("?")
      loc = node.location

      add_mutation(
        offset: loc.start_offset,
        length: loc.length,
        replacement: "nil",
        node: node
      )
    end

    super
  end
end
