# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::BlockPassRemoval < Evilution::Mutator::Base
  def visit_call_node(node)
    block_node = node.block
    if block_node.is_a?(Prism::BlockArgumentNode)
      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: build_replacement(node, block_node),
        node: node
      )
    end

    super
  end

  private

  # Drop the block-pass argument plus the trailing comma it leaves behind, and
  # collapse the resulting `()` if the block-pass was the only argument.
  def build_replacement(node, block_node)
    call_start = node.location.start_offset
    node_end = call_start + node.location.length
    block_start = block_node.location.start_offset
    block_end = block_start + block_node.location.length

    prefix = @file_source.byteslice(call_start...block_start).rstrip.sub(/,\s*\z/, "")
    suffix = @file_source.byteslice(block_end...node_end)
    "#{prefix}#{suffix}".sub(/\(\s*\)/, "")
  end
end
