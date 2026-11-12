# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::MethodCallRemoval < Evilution::Mutator::Base
  extend Evilution::Mutator::ConstantValueSubjects

  def visit_call_node(node)
    if node.receiver && !constant_value_freeze?(node)
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
