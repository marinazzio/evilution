# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ArrayLiteral < Evilution::Mutator::Base
  def visit_array_node(node)
    if node.opening_loc && node.elements.any?
      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "[]",
        node: node
      )

      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "nil",
        node: node
      )

      mutate_delete_elements(node.elements)
    end

    super
  end

  private

  # Delete each element in turn: a survivor means no example checks that
  # element. A single element is left to the `[]` replacement. A heredoc
  # element stays: its body sits after the closing bracket, so one cut cannot
  # take both, and the cut that does not parse is dropped.
  def mutate_delete_elements(elements)
    return if elements.one?

    elements.each_with_index do |element, index|
      offset, stop = deletion_range(elements, index)
      add_mutation(offset:, length: stop - offset, replacement: "", node: element, skip_unparseable: true)
    end
  end

  # An element goes with the separator after it; the last one, with the
  # separator before it, so a trailing comma stays where it was.
  def deletion_range(elements, index)
    element = elements[index]
    following = elements[index + 1]
    return [element.location.start_offset, following.location.start_offset] if following

    [elements[index - 1].location.end_offset, element.location.end_offset]
  end
end
