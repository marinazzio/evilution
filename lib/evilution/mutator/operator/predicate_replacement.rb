# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::PredicateReplacement < Evilution::Mutator::Base
  def visit_call_node(node)
    if node.name.to_s.end_with?("?")
      loc = node.location

      add_mutation(
        offset: loc.start_offset,
        length: loc.length,
        replacement: "true",
        node: node
      )

      add_mutation(
        offset: loc.start_offset,
        length: loc.length,
        replacement: "false",
        node: node
      )
    end

    super
  end
end
