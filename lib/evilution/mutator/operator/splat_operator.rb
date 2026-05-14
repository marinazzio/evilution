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

  # KeywordHashNode wraps call-arg kwargs + `**splat`. When an explicit
  # `k: v` precedes a `**opts` splat in the same call, demoting `**opts` to
  # bare `opts` puts a positional after a keyword and Ruby rejects it
  # (`bar(k: v, opts)` is a syntax error). Mark such splats so
  # `visit_assoc_splat_node` skips them. Splats that come BEFORE any kwarg
  # (`bar(**opts, k: v)`) are still safe — positional-before-keyword is fine.
  def visit_keyword_hash_node(node)
    seen_kwarg = false
    node.elements.each do |el|
      if el.is_a?(Prism::AssocSplatNode) && seen_kwarg
        kwarg_preceded_splats.add(el)
      elsif el.is_a?(Prism::AssocNode)
        seen_kwarg = true
      end
    end

    super
  end

  def visit_assoc_splat_node(node)
    return super if node.value.nil?
    return super if hash_elements.include?(node)
    return super if kwarg_preceded_splats.include?(node)

    mutate_remove_double_splat(node)

    super
  end

  private

  def hash_elements
    @hash_elements ||= Set.new.compare_by_identity
  end

  def kwarg_preceded_splats
    @kwarg_preceded_splats ||= Set.new.compare_by_identity
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
