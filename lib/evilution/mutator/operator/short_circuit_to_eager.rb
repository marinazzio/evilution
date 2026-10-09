# frozen_string_literal: true

require_relative "../operator"

# Make a short-circuit operator evaluate both sides: `a && b` becomes
# `a & b`, `a || b` becomes `a | b`.
#
# A survivor means no example depends on the right side being skipped: it
# guards nothing (a nil receiver, a side effect), and both sides are plain
# booleans, since `&` and `|` give another value for anything else.
#
# `&` and `|` bind tighter than `&&` and `||`, so an operand that would
# regroup (`a == 1 && b` is not `a == 1 & b`) is parenthesized.
class Evilution::Mutator::Operator::ShortCircuitToEager < Evilution::Mutator::Base
  def visit_and_node(node)
    mutate_to_eager(node, "&")
    super
  end

  def visit_or_node(node)
    mutate_to_eager(node, "|")
    super
  end

  private

  # An operand that only jumps (`a || return`) has no value to pass on; the
  # result does not parse and is dropped.
  def mutate_to_eager(node, operator)
    replacement = "#{receiver_source(node.left)} #{operator} #{receiver_source(node.right)}"

    replace_span(node:, target: node, replacement:)
  end
end
