# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::RetryRemoval < Evilution::Mutator::Base
  def visit_retry_node(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "nil",
      node: node
    )

    super
  end
end
