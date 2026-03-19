# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class BlockRemoval < Base
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
    end
  end
end
