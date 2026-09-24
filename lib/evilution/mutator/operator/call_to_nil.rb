# frozen_string_literal: true

require_relative "../operator"

# Replace a method call with `nil`: `user.name` becomes `nil`, and the same
# for implicit-self calls, operator calls and calls carrying a block.
#
# The broadest value-level probe on a call site. The survivor it targets is a
# call whose result is never asserted — the test runs the code but checks
# nothing that depends on what the call returned.
#
# Three positions are skipped as noise. A call in void statement position
# (every statement of a body except the last) has no value to replace;
# deleting it is statement_deletion's job. A call used as the receiver of
# another call turns into `nil.foo`, a NoMethodError any test that reaches it
# kills; the outer call is nil-ified instead. An attribute or index write
# (`a.b = c`, `a[i] = c`) is a side effect, not a value.
class Evilution::Mutator::Operator::CallToNil < Evilution::Mutator::Base
  def call(subject, **)
    @skipped_calls = Set.new
    super
  end

  def visit_statements_node(node)
    @skipped_calls.merge(node.body[...-1])
    super
  end

  def visit_call_node(node)
    @skipped_calls.add(node.receiver)
    mutate_to_nil(node) unless @skipped_calls.include?(node) || node.attribute_write?
    super
  end
end
