# frozen_string_literal: true

require_relative "../operator"

# Swap the values of neighbouring keyword arguments, keeping the keys:
# `compute(x: a, y: b)` becomes `compute(x: b, y: a)`.
#
# A survivor means no example tells the two values apart — the keyword form
# of the defect ArgumentOrderPermutation probes for positional arguments.
#
# Only keyword arguments written in the call are swapped: a braced hash is a
# single positional argument whose pairs are data. A double splat stays in
# place, and identical values are not swapped, since that would reproduce the
# original call. A shorthand key (`compute(a:, b:)`) has no value of its own
# to move, so the swap spells it out: `compute(a: b, b: a)`.
class Evilution::Mutator::Operator::KeywordValueSwap < Evilution::Mutator::Base
  def visit_call_node(node)
    swap_keyword_values(node)
    super
  end

  def visit_super_node(node)
    swap_keyword_values(node)
    super
  end

  def visit_yield_node(node)
    swap_keyword_values(node)
    super
  end

  private

  def swap_keyword_values(node)
    return if node.arguments.nil?

    node.arguments.arguments.grep(Prism::KeywordHashNode).each do |keywords|
      pairs = keywords.elements.grep(Prism::AssocNode)
      pairs.each_cons(2) do |left, right|
        emit_swap(node, left, right) unless value_text(left) == value_text(right)
      end
    end
  end

  # Whatever separates the two pairs — the comma, a double splat, line breaks,
  # comments — stays between them, so the call keeps its layout.
  def emit_swap(node, left, right)
    start_offset = left.location.start_offset

    add_mutation(
      offset: start_offset,
      length: right.location.end_offset - start_offset,
      replacement: "#{key_text(left)}#{value_text(right)}#{source_between(left, right)}" \
                   "#{key_text(right)}#{value_text(left)}",
      node: node
    )
  end

  def source_between(left, right)
    byteslice_source(left.location.end_offset, right.location.start_offset - left.location.end_offset)
  end

  # The key with everything up to its value: `x: `, `"x" => `.
  def key_text(pair)
    return "#{pair.key.slice} " if pair.value.is_a?(Prism::ImplicitNode)

    byteslice_source(pair.location.start_offset, pair.value.location.start_offset - pair.location.start_offset)
  end

  # A shorthand key stands for the local variable or method of the same name.
  def value_text(pair)
    value = pair.value
    value.is_a?(Prism::ImplicitNode) ? value.value.name.to_s : value.slice
  end
end
