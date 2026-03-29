# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::IndexAssignmentRemoval < Evilution::Mutator::Base
  def visit_call_node(node)
    if node.name == :[]= && node.receiver
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
