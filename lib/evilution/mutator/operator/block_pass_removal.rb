# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::BlockPassRemoval < Evilution::Mutator::Base
  def visit_call_node(node)
    if node.block.is_a?(Prism::BlockArgumentNode)
      block_node = node.block
      call_end = block_node.location.start_offset
      call_start = node.location.start_offset
      call_without_block = @file_source.byteslice(call_start...call_end).rstrip

      # Remove trailing opening paren if the only argument was the block pass
      call_without_block = call_without_block.sub(/\(\s*\z/, "") if node.arguments.nil? || node.arguments.arguments.empty?

      add_mutation(
        offset: call_start,
        length: node.location.length,
        replacement: call_without_block,
        node: node
      )
    end

    super
  end
end
