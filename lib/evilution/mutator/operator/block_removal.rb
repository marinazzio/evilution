# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::BlockRemoval < Evilution::Mutator::Base
  def visit_call_node(node)
    if node.block
      block_node = node.block
      call_end = block_node.location.start_offset
      call_start = node.location.start_offset
      call_without_block = @file_source.byteslice(call_start...call_end).rstrip

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
