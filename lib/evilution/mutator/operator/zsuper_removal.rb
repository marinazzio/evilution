# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ZsuperRemoval < Evilution::Mutator::Base
  def visit_forwarding_super_node(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "nil",
      node: node
    )

    super
  end
end
