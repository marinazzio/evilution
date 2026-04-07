# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::EqualityToIdentity < Evilution::Mutator::Base
  def visit_call_node(node)
    if node.name == :== && node.receiver && node.arguments
      receiver_text = @file_source.byteslice(node.receiver.location.start_offset, node.receiver.location.length)
      arg = node.arguments.arguments.first
      arg_text = @file_source.byteslice(arg.location.start_offset, arg.location.length)

      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "#{receiver_text}.equal?(#{arg_text})",
        node: node
      )
    end

    super
  end
end
