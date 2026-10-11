# frozen_string_literal: true

require_relative "../operator"

# Replace an index write with the value it assigns: `cache[key] = value`
# becomes `value`.
#
# An index write evaluates to the assigned value, so the mutant returns just
# what the original did — only the store is gone. A survivor means the tests
# check what was computed and never that it was kept. That is what sets it
# apart from deleting the statement or turning it into `nil`, both of which
# also change the result.
#
# A write in void statement position is skipped: with its value discarded,
# the mutant is statement_deletion's. Operator writes (`a[b] ||= c`) and
# index targets of a multiple assignment are not calls and are left alone.
class Evilution::Mutator::Operator::IndexWriteToValue < Evilution::Mutator::Base
  def call(subject, **)
    @void_statements = Set.new
    super
  end

  def visit_statements_node(node)
    @void_statements.merge(node.body[...-1])
    super
  end

  def visit_call_node(node)
    promote_child(node, argument_nodes(node).last) if node.name == :[]= && !@void_statements.include?(node)
    super
  end
end
