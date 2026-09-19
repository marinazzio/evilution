# frozen_string_literal: true

require_relative "../operator"

# Replace a whole method body with a bare `raise`: `def foo; body; end` becomes
# `def foo; raise; end`.
#
# A survivor means no example ever calls the method on a path it asserts, so
# the method is either dead or reached only where the suite looks away. Where
# body-to-nil (MethodBodyReplacement) asks whether the return value matters,
# this asks the prior question of whether the call happens at all — a method
# whose result is discarded survives the nil mutation but not this one.
class Evilution::Mutator::Operator::MethodBodyToRaise < Evilution::Mutator::Base
  def visit_def_node(node)
    replace_body_with_raise(node)
    super
  end

  private

  def replace_body_with_raise(node)
    statements = body_statements(node.body)
    return if statements.nil?
    return if single_raise?(statements)

    location = statements.location

    add_mutation(
      offset: location.start_offset,
      length: location.length,
      replacement: "raise",
      node: node
    )
  end

  # A method-level rescue/ensure (`def foo; stmts; rescue; ...; end`) makes the
  # body a BeginNode whose location spans the entire `def...end`, keyword and
  # matching `end` included. Replacing that range would delete the method
  # framing and leave a bare `raise` at the enclosing scope, so only the leading
  # statements are replaceable. Returns nil for a rescue/ensure-only body, where
  # there are none, and for an empty method, whose body is nil outright.
  def body_statements(body)
    return body unless body.is_a?(Prism::BeginNode)

    body.statements
  end

  # A body that already consists of one unconditional raise would mutate to a
  # near-equivalent: `raise NotImplementedError` -> `raise` only changes the
  # error class, which is what RaiseArgumentStrip (#1537) probes. Arguments are
  # not inspected, so a bare raise is skipped on the same rule.
  def single_raise?(statements)
    body = statements.body
    return false unless body.length == 1

    only = body.first
    only.is_a?(Prism::CallNode) && only.name == :raise && only.receiver.nil?
  end
end
