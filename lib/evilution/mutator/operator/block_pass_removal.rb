# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::BlockPassRemoval < Evilution::Mutator::Base
  def visit_call_node(node)
    if node.block.is_a?(Prism::BlockArgumentNode)
      block_node = node.block
      call_start = node.location.start_offset
      node_end = call_start + node.location.length
      block_end = block_node.location.start_offset + block_node.location.length

      prefix = @file_source.byteslice(call_start...block_node.location.start_offset).rstrip
      suffix = @file_source.byteslice(block_end...node_end)

      # Clean up: remove trailing comma from prefix, remove empty parens
      prefix = prefix.sub(/,\s*\z/, "")
      replacement = "#{prefix}#{suffix}".sub(/\(\s*\)/, "")

      add_mutation(
        offset: call_start,
        length: node.location.length,
        replacement: replacement,
        node: node
      )
    end

    super
  end
end
