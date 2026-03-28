# frozen_string_literal: true

class Evilution::Mutator::Operator::MethodCallRemoval < Evilution::Mutator::Base
  def visit_call_node(node)
    if node.receiver
      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: node.receiver.slice,
        node: node
      )
    end

    super
  end
end
