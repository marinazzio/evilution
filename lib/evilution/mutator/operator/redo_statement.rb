# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::RedoStatement < Evilution::Mutator::Base
  def visit_redo_node(node)
    loc = node.location

    add_mutation(
      offset: loc.start_offset,
      length: loc.length,
      replacement: "nil",
      node: node
    )

    super
  end
end
