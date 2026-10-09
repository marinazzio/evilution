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
      mutate_promote_only_element(node)
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

    elements.each_index { |index| delete_element(elements, index) }
  end

  # `[x]` becomes `x`: a survivor means the wrapping does not matter, as when
  # the caller flattens or splats the value anyway. The words of `%w[a]` are
  # not written as expressions and stay. An element that is not an expression
  # on its own (`*x`, the bare keywords of `[a: 1]`) does not parse once
  # promoted and is dropped, and so is a heredoc, whose body cannot follow
  # the cut.
  def mutate_promote_only_element(node)
    return unless node.elements.one? && node.opening == "["

    replace_span(node:, target: node, replacement: receiver_source(node.elements.first))
  end
end
