# frozen_string_literal: true

require_relative "../operator"

# Replace a one-line pattern match with `false`: `x in Integer` becomes
# `false`.
#
# The mutant differs from the original only on inputs the pattern actually
# matches, so a survivor means no test ever feeds it a matching value -- the
# true path of the predicate is unexercised.
#
# Only Prism::MatchPredicateNode is mutated. Its sibling MatchRequiredNode
# (`x => Integer`) raises NoMatchingPatternError rather than returning a
# boolean, so `false` would not stand in for it.
class Evilution::Mutator::Operator::PatternPredicate < Evilution::Mutator::Base
  def visit_match_predicate_node(node)
    location = node.location

    add_mutation(
      offset: location.start_offset,
      length: location.length,
      replacement: "false",
      node: node
    )

    super
  end
end
