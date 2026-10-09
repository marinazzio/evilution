# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::HashLiteral < Evilution::Mutator::Base
  def visit_hash_node(node)
    if node.elements.any?
      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "{}",
        node: node
      )

      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "nil",
        node: node
      )

      mutate_delete_pairs(node.elements)
    end

    super
  end

  private

  # Delete each key/value pair in turn: a survivor means no example checks
  # that key. A single element is left to the `{}` replacement. A `**splat`
  # is not a pair and stays. So does a pair holding a heredoc: its body sits
  # after the closing brace, so one cut cannot take both, and the cut that
  # does not parse is dropped.
  def mutate_delete_pairs(elements)
    return if elements.one?

    elements.each_with_index do |element, index|
      delete_element(elements, index) if element.is_a?(Prism::AssocNode)
    end
  end
end
