# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::BitwiseComplement < Evilution::Mutator::Base
  def visit_call_node(node)
    if node.name == :~ && node.receiver && node.arguments.nil?
      loc = node.message_loc
      receiver_loc = node.receiver.location

      # Remove ~: replace entire ~expr with just the receiver expression
      receiver_source = byteslice_source(receiver_loc.start_offset, receiver_loc.length)
      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: receiver_source,
        node: node
      )

      # Swap ~ with unary minus
      add_mutation(
        offset: loc.start_offset,
        length: loc.length,
        replacement: "-",
        node: node
      )
    end

    super
  end
end
