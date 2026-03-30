# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::PatternMatchingArray < Evilution::Mutator::Base
  def visit_array_pattern_node(node)
    mutate_array_elements(node)
    super
  end

  def visit_find_pattern_node(node)
    mutate_find_elements(node)
    super
  end

  private

  def mutate_array_elements(node)
    requireds = node.requireds
    posts = node.posts
    rest = node.rest
    elements = requireds + posts
    return if elements.empty?

    elements.each_with_index do |_element, index|
      remove_array_element(node, requireds, posts, rest, index) if elements.length > 1
      wildcard_array_element(node, requireds, posts, rest, index)
    end
  end

  def remove_array_element(node, requireds, posts, rest, skip_index)
    parts = build_array_parts(requireds, posts, rest, skip_index: skip_index)
    replace_pattern(node, parts)
  end

  def wildcard_array_element(node, requireds, posts, rest, wildcard_index)
    parts = build_array_parts(requireds, posts, rest, wildcard_index: wildcard_index)
    replace_pattern(node, parts)
  end

  def build_array_parts(requireds, posts, rest, skip_index: nil, wildcard_index: nil)
    parts = []
    requireds.each_with_index do |req, i|
      next if i == skip_index

      parts << (i == wildcard_index ? "_" : source_for(req))
    end
    parts << source_for(rest) if rest
    posts.each_with_index do |post, i|
      adjusted = requireds.length + i
      next if adjusted == skip_index

      parts << (adjusted == wildcard_index ? "_" : source_for(post))
    end
    parts
  end

  def mutate_find_elements(node)
    return if node.requireds.empty?

    node.requireds.each_with_index do |_element, index|
      remove_find_element(node, index) if node.requireds.length > 1
      wildcard_find_element(node, index)
    end
  end

  def remove_find_element(node, skip_index)
    parts = [source_for(node.left)]
    node.requireds.each_with_index do |req, i|
      parts << source_for(req) unless i == skip_index
    end
    parts << source_for(node.right)
    replace_pattern(node, parts)
  end

  def wildcard_find_element(node, wildcard_index)
    parts = [source_for(node.left)]
    node.requireds.each_with_index do |req, i|
      parts << (i == wildcard_index ? "_" : source_for(req))
    end
    parts << source_for(node.right)
    replace_pattern(node, parts)
  end

  def replace_pattern(node, parts)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "[#{parts.join(", ")}]",
      node: node
    )
  end

  def source_for(node)
    @file_source.byteslice(node.location.start_offset, node.location.length)
  end
end
