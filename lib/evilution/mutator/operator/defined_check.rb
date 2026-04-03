# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::DefinedCheck < Evilution::Mutator::Base
  def visit_defined_node(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "true",
      node: node
    )

    super
  end
end
