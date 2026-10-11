# frozen_string_literal: true

require_relative "../operator"

# Send an index read to `self` instead of its receiver: `hash[key]` becomes
# `self[key]`, arguments untouched.
#
# The survivor it targets lives in a class that defines its own `#[]` — a
# collection or a wrapper that also holds the thing it indexes — where the
# tests never tell the two lookups apart. Anywhere else the mutant raises
# NoMethodError, which any test reaching the line kills.
#
# Index writes are left alone: `a[b] = c` is a different method, and the
# operator-write forms (`a[b] ||= c`) are not calls at all.
class Evilution::Mutator::Operator::IndexReceiverToSelf < Evilution::Mutator::Base
  def visit_call_node(node)
    replace_span(node: node, target: node.receiver, replacement: "self") if node.name == :[]
    super
  end
end
