# frozen_string_literal: true

require_relative "../operator"

# Replace a loop body with a bare `raise`: `while c; body; end` becomes
# `while c; raise; end`.
#
# A survivor means no test ever enters the loop, so the body is either dead
# or reached only by paths the suite never exercises. The raise terminates
# the loop on its first iteration, which is what makes this safe where
# body-to-nil is not: nil-ing a body that advances the predicate spins until
# the per-mutation timeout (EV-170m.7).
class Evilution::Mutator::Operator::LoopBodyToRaise < Evilution::Mutator::Base
  def visit_while_node(node)
    replace_body_with_raise(node)
    super
  end

  def visit_until_node(node)
    replace_body_with_raise(node)
    super
  end

  private

  def replace_body_with_raise(node)
    statements = body_statements(node)
    return if statements.nil?
    return if bare_raise?(statements)

    location = statements.location

    add_mutation(
      offset: location.start_offset,
      length: location.length,
      replacement: "raise",
      node: node
    )
  end

  # A post-form loop (`begin ... end while c`) hangs its body off a BeginNode,
  # and that node's own span is what WhileNode#statements reports. Editing the
  # outer span would rewrite the loop as `raise while c`, which checks the
  # predicate first and so no longer runs the body unconditionally -- exactly
  # the property this mutation exists to probe. Reach through to the inner
  # statements instead and leave `begin ... end while c` standing.
  #
  # begin_modifier? is set only for that post-form, where the grammar
  # guarantees the single wrapped statement is the BeginNode.
  def body_statements(node)
    statements = node.statements
    return statements unless node.begin_modifier?

    statements.body.first.statements
  end

  # A body that already raises unconditionally would mutate to itself.
  def bare_raise?(statements)
    body = statements.body
    return false unless body.length == 1

    only = body.first
    only.is_a?(Prism::CallNode) &&
      only.name == :raise &&
      only.arguments.nil? &&
      only.receiver.nil?
  end
end
