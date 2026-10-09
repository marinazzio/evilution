# frozen_string_literal: true

require_relative "../operator"

# Turn a memoizing assignment into a plain one: `@x ||= expr` becomes
# `@x = expr`, so the value is computed again on every call.
#
# A survivor means no example tells one computation from several: nothing
# counts the calls behind the value, and nothing depends on getting the same
# object back.
class Evilution::Mutator::Operator::MemoizationBreak < Evilution::Mutator::Base
  def visit_instance_variable_or_write_node(node)
    operator = node.operator_loc
    add_mutation(offset: operator.start_offset, length: operator.length, replacement: "=", node: node)

    super
  end
end
