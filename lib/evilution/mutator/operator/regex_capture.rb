# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::RegexCapture < Evilution::Mutator::Base
  def visit_numbered_reference_read_node(node)
    mutate_replace_with_nil(node)
    mutate_swap_number(node)

    super
  end

  private

  def mutate_replace_with_nil(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "nil",
      node: node
    )
  end

  def mutate_swap_number(node)
    number = node.number

    if number > 1
      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "$#{number - 1}",
        node: node
      )
    end

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "$#{number + 1}",
      node: node
    )
  end
end
