# frozen_string_literal: true

require_relative "../operator"

# Replace an attribute or index write with the matching read: `a.foo = b`
# becomes `a.foo`, `a[i] = b` becomes `a[i]`.
#
# A survivor means nothing observes the write. Only positions
# statement_deletion does not reach are mutated: a write that is one of
# several statements in a body is already deleted there, and turning it into
# a read differs from that only by the reader call.
class Evilution::Mutator::Operator::AttributeWriteToRead < Evilution::Mutator::Base
  def call(subject, **)
    @deletable_statements = Set.new
    super
  end

  def visit_statements_node(node)
    @deletable_statements.merge(node.body) if node.body.length > 1
    super
  end

  def visit_call_node(node)
    mutate_to_read(node) if node.attribute_write? && !@deletable_statements.include?(node)
    super
  end

  private

  def mutate_to_read(node)
    read_length = node.message_loc.end_offset - node.start_offset
    replace_span(node: node, target: node, replacement: byteslice_source(node.start_offset, read_length))
  end
end
