# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ReceiverReplacement < Evilution::Mutator::Base
  def visit_call_node(node)
    if node.receiver.is_a?(Prism::SelfNode)
      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: call_without_self_text(node),
        node: node
      )
    end

    super
  end

  private

  def call_without_self_text(node)
    message_start = node.message_loc.start_offset
    call_end = node.location.start_offset + node.location.length
    @file_source.byteslice(message_start, call_end - message_start)
  end
end
