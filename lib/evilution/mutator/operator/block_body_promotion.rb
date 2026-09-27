# frozen_string_literal: true

require_relative "../operator"

# Replace a call with its parameter-less block's body, run once in place:
# `Base.transaction { account.save! }` becomes `account.save!`, and
# `3.times { retry_call }` becomes `retry_call`. A multi-statement body is
# grouped in parentheses so it still evaluates to its last statement where
# the call's value is used.
#
# A survivor means the wrapping call is never observed: a transaction whose
# rollback no test triggers, a lock nothing contends for, an iteration count
# nothing checks.
#
# Blocks with parameters (including `_1` / `it` and block-locals) are
# skipped — the unwrapped body would reference a variable that no longer
# exists; explicitly empty pipes `{ || ... }` count as parameter-less. So are
# bodies with a rescue / ensure clause, and bodies using `break` / `next` /
# `redo`, which do not parse outside a block and are dropped by the parse
# guard.
class Evilution::Mutator::Operator::BlockBodyPromotion < Evilution::Mutator::Base
  def visit_call_node(node)
    block = node.block
    unwrap(node, block.body) if block.is_a?(Prism::BlockNode) && parameterless?(block.parameters)
    super
  end

  private

  # No parameters at all, or explicitly empty pipes `{ || ... }`. Block-local
  # variables (`{ |;tmp| ... }`) count as parameters: unwrapping would turn
  # them into method locals.
  def parameterless?(parameters)
    parameters.nil? ||
      (parameters.is_a?(Prism::BlockParametersNode) && parameters.parameters.nil? && parameters.locals.empty?)
  end

  def unwrap(node, body)
    return unless body.is_a?(Prism::StatementsNode)

    statements = body.body
    replacement = statements.length == 1 ? source_of(statements.first) : "(#{source_of(body)})"
    replace_span(node: node, target: node, replacement: replacement)
  end
end
