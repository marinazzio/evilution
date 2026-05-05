# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::EqualityToIdentity < Evilution::Mutator::Base
  def visit_call_node(node)
    if node.name == :== && node.receiver && node.arguments
      receiver_text = loc_text(node.receiver.location)
      arg_text = loc_text(node.arguments.arguments.first.location)

      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "#{receiver_text}.equal?(#{arg_text})",
        node: node
      )
    end

    super
  end

  private

  def loc_text(loc)
    @file_source.byteslice(loc.start_offset, loc.length)
  end
end
