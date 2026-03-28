# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ClassVariableWrite < Evilution::Mutator::Base
  def visit_class_variable_write_node(node)
    # Mutation 1: remove assignment, keep only the value expression
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: node.value.slice,
      node: node
    )

    # Mutation 2: replace value with nil
    add_mutation(
      offset: node.value.location.start_offset,
      length: node.value.location.length,
      replacement: "nil",
      node: node
    )

    super
  end
end
