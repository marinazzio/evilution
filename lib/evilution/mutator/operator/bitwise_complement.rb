# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::BitwiseComplement < Evilution::Mutator::Base
  def visit_call_node(node)
    if node.name == :~ && node.receiver && node.arguments.nil?
      emit_remove_complement(node)
      emit_swap_to_minus(node)
    end

    super
  end

  private

  # Replace `~expr` with just `expr`.
  def emit_remove_complement(node)
    receiver_loc = node.receiver.location
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: byteslice_source(receiver_loc.start_offset, receiver_loc.length),
      node: node
    )
  end

  # Swap `~` with unary minus.
  def emit_swap_to_minus(node)
    loc = node.message_loc
    add_mutation(
      offset: loc.start_offset,
      length: loc.length,
      replacement: "-",
      node: node
    )
  end
end
