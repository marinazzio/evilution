# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::LocalVariableAssignment < Evilution::Mutator::Base
  def visit_local_variable_write_node(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: node.value.slice,
      node: node
    )

    super
  end
end
