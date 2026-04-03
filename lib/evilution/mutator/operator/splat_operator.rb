# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::SplatOperator < Evilution::Mutator::Base
  def visit_splat_node(node)
    mutate_remove_splat(node) if node.expression

    super
  end

  def visit_hash_node(node)
    node.elements.each { |el| hash_elements.add(el) }
    super
  end

  def visit_assoc_splat_node(node)
    mutate_remove_double_splat(node) if node.value && !hash_elements.include?(node)

    super
  end

  private

  def hash_elements
    @hash_elements ||= Set.new.compare_by_identity
  end

  def mutate_remove_splat(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: node.expression.slice,
      node: node
    )
  end

  def mutate_remove_double_splat(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: node.value.slice,
      node: node
    )
  end
end
