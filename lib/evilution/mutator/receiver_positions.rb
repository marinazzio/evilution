# frozen_string_literal: true

require_relative "../mutator"

# Visits every node that sends a message to a receiver and hands that
# receiver to #receiver_found, before the receiver itself is visited.
#
# A plain call is one such node, but not the only one. An operator or
# logical write on an attribute or an index (`a.b += c`, `a[b] ||= c`) and
# an attribute or index target of a multiple assignment (`a.b, c[d] = e`)
# each hold their receiver in a node of their own. An operator that treats
# "the receiver of a call" specially — replacing it with `nil` only earns a
# NoMethodError — has to mean all of them.
#
# The includer defines #receiver_found(node). `node` is nil where the
# message has no explicit receiver.
module Evilution::Mutator::ReceiverPositions
  def visit_call_node(node)
    receiver_found(node.receiver)
    super
  end

  def visit_call_operator_write_node(node)
    receiver_found(node.receiver)
    super
  end

  def visit_call_or_write_node(node)
    receiver_found(node.receiver)
    super
  end

  def visit_call_and_write_node(node)
    receiver_found(node.receiver)
    super
  end

  def visit_index_operator_write_node(node)
    receiver_found(node.receiver)
    super
  end

  def visit_index_or_write_node(node)
    receiver_found(node.receiver)
    super
  end

  def visit_index_and_write_node(node)
    receiver_found(node.receiver)
    super
  end

  def visit_call_target_node(node)
    receiver_found(node.receiver)
    super
  end

  def visit_index_target_node(node)
    receiver_found(node.receiver)
    super
  end
end
