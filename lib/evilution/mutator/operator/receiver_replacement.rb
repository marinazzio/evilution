# frozen_string_literal: true

class Evilution::Mutator::Operator::ReceiverReplacement < Evilution::Mutator::Base
  def visit_call_node(node)
    if node.receiver.is_a?(Prism::SelfNode)
      call_without_self = @file_source.byteslice(
        node.message_loc.start_offset,
        node.location.start_offset + node.location.length - node.message_loc.start_offset
      )

      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: call_without_self,
        node: node
      )
    end

    super
  end
end
