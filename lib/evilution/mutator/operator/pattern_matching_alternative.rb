# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::PatternMatchingAlternative < Evilution::Mutator::Base
  def visit_alternation_pattern_node(node)
    remove_left(node)
    remove_right(node)
    swap_order(node)
    super
  end

  private

  def remove_left(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: source_for(node.right),
      node: node
    )
  end

  def remove_right(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: source_for(node.left),
      node: node
    )
  end

  def swap_order(node)
    operator = @file_source.byteslice(node.operator_loc.start_offset, node.operator_loc.length)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "#{source_for(node.right)} #{operator} #{source_for(node.left)}",
      node: node
    )
  end

  def source_for(node)
    @file_source.byteslice(node.location.start_offset, node.location.length)
  end
end
