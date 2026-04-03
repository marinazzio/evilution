# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::YieldStatement < Evilution::Mutator::Base
  def visit_yield_node(node)
    mutate_remove_yield(node)

    if node.arguments
      mutate_remove_arguments(node)
      mutate_replace_value_with_nil(node)
    end

    super
  end

  private

  def mutate_remove_yield(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "nil",
      node: node
    )
  end

  def mutate_remove_arguments(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "yield",
      node: node
    )
  end

  def mutate_replace_value_with_nil(node)
    replacement = if node.lparen_loc
                    "yield(nil)"
                  else
                    "yield nil"
                  end

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: replacement,
      node: node
    )
  end
end
