# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::MultipleAssignment < Evilution::Mutator::Base
  def visit_multi_write_node(node)
    lefts = node.lefts
    values = node.value.is_a?(Prism::ArrayNode) ? node.value.elements : nil

    if values && lefts.length == values.length && lefts.length >= 2 && node.rest.nil?
      mutate_target_removal(node, lefts, values)
      mutate_swap(node, lefts, values) if lefts.length == 2
    end

    super
  end

  private

  def mutate_target_removal(node, lefts, values)
    lefts.each_index do |i|
      remaining_lefts = lefts.each_with_index.filter_map { |l, j| l.slice if j != i }
      remaining_values = values.each_with_index.filter_map { |v, j| v.slice if j != i }

      replacement = "#{remaining_lefts.join(", ")} = #{remaining_values.join(", ")}"

      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: replacement,
        node: node
      )
    end
  end

  def mutate_swap(node, lefts, values)
    swapped_lefts = "#{lefts[1].slice}, #{lefts[0].slice}"
    replacement = "#{swapped_lefts} = #{values.map(&:slice).join(", ")}"

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: replacement,
      node: node
    )
  end
end
