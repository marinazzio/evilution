# frozen_string_literal: true

require_relative "../operator"

# Drop one `in` clause from a `case/in`, leaving the rest of the arms in
# place.
#
# Input that used to match the removed pattern now falls through to a later
# arm, to the `else`, or -- with neither -- raises NoMatchingPatternError. A
# survivor means the suite never exercises that arm, so its pattern could be
# deleted outright without any test noticing.
#
# Pattern matching had no visitor at all before this operator: the case/in
# grammar is a CaseMatchNode of InNodes, unrelated to the CaseNode/WhenNode
# pair CaseWhen handles.
class Evilution::Mutator::Operator::CaseIn < Evilution::Mutator::Base
  def visit_case_match_node(node)
    remove_in_clauses(node)
    remove_else_branch(node)
    super
  end

  private

  # A case/in needs at least one arm to parse, so a lone clause stays put.
  def remove_in_clauses(node)
    return if node.conditions.length < 2

    node.conditions.each do |in_node|
      location = in_node.location

      add_mutation(
        offset: location.start_offset,
        length: location.length,
        replacement: "",
        node: in_node
      )
    end
  end

  # Without an else, an unmatched value raises NoMatchingPatternError rather
  # than falling through, so a survivor means nothing in the suite reaches the
  # fallback.
  #
  # An empty else body is worth removing here, which is where this parts ways
  # with CaseWhen: a case/when yields nil whether its else is empty or absent,
  # but an empty case/in else yields nil while an absent one raises. Prism
  # reports no statements for that shape, so the edit covers the keyword alone.
  def remove_else_branch(node)
    else_clause = node.else_clause
    return if else_clause.nil?

    keyword_location = else_clause.else_keyword_loc
    statements = else_clause.statements
    end_offset = statements.nil? ? keyword_location.end_offset : statements.location.end_offset

    add_mutation(
      offset: keyword_location.start_offset,
      length: end_offset - keyword_location.start_offset,
      replacement: "",
      node: else_clause
    )
  end
end
