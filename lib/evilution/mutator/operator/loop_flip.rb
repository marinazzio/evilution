# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::LoopFlip < Evilution::Mutator::Base
  def visit_while_node(node)
    add_mutation(
      offset: node.keyword_loc.start_offset,
      length: node.keyword_loc.length,
      replacement: "until",
      node: node
    )

    super
  end

  def visit_until_node(node)
    add_mutation(
      offset: node.keyword_loc.start_offset,
      length: node.keyword_loc.length,
      replacement: "while",
      node: node
    )

    super
  end
end
