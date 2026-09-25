# frozen_string_literal: true

require_relative "../operator"

# Drop a call's whole argument list: `combine(a, b)` becomes `combine`,
# `normalize(value)` becomes `normalize`. Every argument kind goes —
# positional, splat, keywords and `...` — while a block-pass stays attached
# (`each_slice(2, &block)` becomes `each_slice(&block)`) and so does a
# literal block.
#
# A kill by ArgumentError proves arity is asserted; a survivor means the
# arguments never mattered. argument_removal drops one argument at a time and
# only from calls with two or more.
#
# Operator methods (`a + b`, `a[i]`) are left to binary operand promotion and
# attribute writes to attribute_write_to_read.
class Evilution::Mutator::Operator::ArgumentListRemoval < Evilution::Mutator::Base
  IDENTIFIER = /\A[[:alpha:]_]/
  private_constant :IDENTIFIER

  def visit_call_node(node)
    remove_argument_list(node) if removable?(node)
    super
  end

  private

  def removable?(node)
    node.arguments && node.message_loc && node.name.match?(IDENTIFIER) && !node.attribute_write?
  end

  def remove_argument_list(node)
    block_pass = node.block if node.block.is_a?(Prism::BlockArgumentNode)
    start = node.message_loc.end_offset

    add_mutation(
      offset: start,
      length: argument_list_end(node, block_pass) - start,
      replacement: block_pass ? "(#{block_pass.slice})" : "",
      node: node
    )
  end

  # Without parentheses the list ends at its last element: the block-pass
  # when there is one (it always comes last), else the last argument. The
  # call node itself would reach past a literal `do ... end` block.
  def argument_list_end(node, block_pass)
    return node.closing_loc.end_offset if node.closing_loc

    (block_pass || node.arguments).end_offset
  end
end
