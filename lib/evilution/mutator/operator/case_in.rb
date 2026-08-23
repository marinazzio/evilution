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
end
