# frozen_string_literal: true

require_relative "../operator"
require_relative "../../ast/regexp_pattern"

# Delete one branch of a regexp alternation at a time: `/cat|dog/` becomes
# `/dog/` and `/cat/`.
#
# A survivor means no example feeds the pattern input that only that branch
# accepts, so the branch could go without any test noticing.
#
# Alternations of more than ten branches are skipped: those are lookup tables
# (generated keyword or emoji lists, for instance), where a deletion per entry
# floods the report with survivors nobody acts on. Deleting a branch can remove
# a group that a backreference or a `\g<name>` call elsewhere in the pattern
# needs, so each mutant is compiled first and dropped if it no longer does.
class Evilution::Mutator::Operator::RegexpAlternationBranchDeletion < Evilution::Mutator::Base
  MAX_BRANCHES = 10

  def visit_regular_expression_node(node)
    pattern = Evilution::AST::RegexpPattern.parse(node)
    if pattern
      pattern.each_expression do |expression, *|
        delete_branches(node, pattern, expression) if expression.is_a?(Regexp::Expression::Alternation)
      end
    end

    super
  end

  private

  def delete_branches(node, pattern, alternation)
    branches = alternation.expressions
    return if branches.length > MAX_BRANCHES

    branches.each_index do |index|
      start_offset, end_offset = deletion_span(pattern, branches, index)
      next unless pattern.compiles?(start_offset, end_offset, "")

      add_mutation(offset: start_offset, length: end_offset - start_offset, replacement: "", node: node)
    end
  end

  # A branch goes with one neighbouring `|`: the one after it for the first
  # branch, the one before it for every other.
  def deletion_span(pattern, branches, index)
    if index.zero?
      [pattern.offsets(branches[0]).first, pattern.offsets(branches[1]).first]
    else
      [pattern.offsets(branches[index - 1]).last, pattern.offsets(branches[index]).last]
    end
  end
end
