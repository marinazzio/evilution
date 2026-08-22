# frozen_string_literal: true

require_relative "../operator"

# Replace the if-branch with the else body and drop the else:
# `if c; x; else; y; end` becomes `if c; y; end`.
#
# The condition still runs and still selects, but both of its outcomes
# change: truthy now yields the else body, falsy now yields nil. That is out
# of reach of the existing conditional operators — ConditionalNegation
# pins the predicate to one branch, ConditionalBranch blanks a body to nil —
# so this survives only when the suite never distinguishes the two branch
# values from each other.
class Evilution::Mutator::Operator::IfBranchSwap < Evilution::Mutator::Base
  def visit_if_node(node)
    swap_branches(node)
    super
  end

  private

  # The edit spans from the start of the if-branch to the end of the else
  # body, which swallows the `else` keyword along with the original branch.
  # It deliberately stops short of ElseNode#location, which runs on to the
  # closing `end` the mutation needs to keep.
  #
  # `subsequent` is an IfNode rather than an ElseNode on an `elsif`, and
  # nil on a bare `if`; neither has an else body to promote. A ternary does
  # reach the edit, but `c ? y` does not parse, so add_mutation drops it.
  def swap_branches(node)
    else_node = node.subsequent
    return unless else_node.is_a?(Prism::ElseNode)

    then_statements = node.statements
    else_statements = else_node.statements
    return if then_statements.nil? || else_statements.nil?

    offset = then_statements.location.start_offset

    add_mutation(
      offset: offset,
      length: else_statements.location.end_offset - offset,
      replacement: source_of(else_statements),
      node: node,
      skip_unparseable: true
    )
  end
end
