# frozen_string_literal: true

require_relative "../operator"

# Replace a block's body with `nil`: `items.map { |item| item * 2 }` becomes
# `items.map { |item| nil }`. Unlike block_removal, the iteration itself
# stays, so a survivor means the block runs but nothing observes what it
# does.
#
# A `do ... rescue ... end` block keeps its rescue / ensure clauses; only
# the main statements become nil.
#
# Blocks that are themselves the loop are skipped — `loop { }` and an
# endless `cycle { }` or `cycle(nil) { }` — since with a nil body nothing
# breaks out and the mutant would hang until the per-mutation timeout (see
# EV-170m.7).
class Evilution::Mutator::Operator::BlockBodyToNil < Evilution::Mutator::Base
  def visit_call_node(node)
    block = node.block
    empty_body(node, block) if block.is_a?(Prism::BlockNode) && !endless_iteration?(node)
    super
  end

  private

  def empty_body(node, block)
    body = block.body
    statements = body.is_a?(Prism::BeginNode) ? body.statements : body
    mutate_to_nil(node, target: statements)
  end

  def endless_iteration?(node)
    case node.name
    when :loop then kernel_receiver?(node.receiver)
    when :cycle then endless_count?(node.arguments)
    end
  end

  # `loop`, `Kernel.loop` or `::Kernel.loop` — not a namespaced `Acme::Kernel`.
  def kernel_receiver?(receiver)
    case receiver
    when nil then true
    when Prism::ConstantReadNode then receiver.name == :Kernel
    when Prism::ConstantPathNode then receiver.parent.nil? && receiver.name == :Kernel
    end
  end

  # `cycle` and `cycle(nil)` both repeat forever.
  def endless_count?(arguments)
    arguments.nil? || (arguments in Prism::ArgumentsNode[arguments: [Prism::NilNode]])
  end
end
