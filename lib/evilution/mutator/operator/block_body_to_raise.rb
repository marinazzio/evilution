# frozen_string_literal: true

require_relative "../operator"

# Replace a block's body with a bare `raise`: `items.map { |item| item * 2 }`
# becomes `items.map { |item| raise }`.
#
# A survivor means no test ever invokes the block — every collection it
# iterates is empty, or the callback is never called. The raise ends the
# block on its first call, so unlike block_body_to_nil a `loop { }` is safe
# here.
#
# A block whose body has a `rescue` clause is skipped: that clause would
# catch the raise, and the mutant would exercise the rescue path instead of
# the invocation. An `ensure` clause does not swallow it and stays.
class Evilution::Mutator::Operator::BlockBodyToRaise < Evilution::Mutator::Base
  def visit_call_node(node)
    block = node.block
    raise_in_body(node, block.body) if block.is_a?(Prism::BlockNode)
    super
  end

  private

  def raise_in_body(node, body)
    if body.is_a?(Prism::BeginNode)
      return if body.rescue_clause

      body = body.statements
    end

    replace_span(node: node, target: body, replacement: "raise")
  end
end
