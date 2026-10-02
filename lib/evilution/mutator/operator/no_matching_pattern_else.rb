# frozen_string_literal: true

require_relative "../operator"

# Give a `case/in` that has no `else` an empty one.
#
# Without an else, a value no pattern matches raises NoMatchingPatternError;
# with an empty one the expression quietly yields nil. A survivor means no
# example feeds the match a value outside its patterns, so nothing asserts
# that such a value is rejected.
#
# The opposite edit, removing an else that is there, belongs to CaseIn.
class Evilution::Mutator::Operator::NoMatchingPatternElse < Evilution::Mutator::Base
  def visit_case_match_node(node)
    add_else(node) if node.else_clause.nil? && !exhaustive?(node)
    super
  end

  private

  def add_else(node)
    offset = node.end_keyword_loc.start_offset

    add_mutation(
      offset: offset,
      length: 0,
      replacement: else_clause_before(offset),
      node: node
    )
  end

  # An `end` on a line of its own gets the else on the line above, indented
  # alike. Otherwise the case is written on one line and the else joins it.
  def else_clause_before(offset)
    line_start = line_start_byte(@file_source, offset)
    indentation = byteslice_source(line_start, offset - line_start)

    indentation.strip.empty? ? "else\n#{indentation}" : "else; "
  end

  # A bare name (`in other`, `in _`) matches every value, so an else after it
  # could never run and adding one would change nothing. A guarded capture is
  # not a bare name: Prism wraps it in the guard's conditional.
  def exhaustive?(node)
    node.conditions.any? { |clause| clause.pattern.is_a?(Prism::LocalVariableTargetNode) }
  end
end
