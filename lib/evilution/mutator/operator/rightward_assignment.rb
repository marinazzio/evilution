# frozen_string_literal: true

require_relative "../operator"

# Turn a rightward pattern match into a pattern predicate: `value => [a, b]`
# becomes `value in [a, b]`.
#
# On a mismatch the original raises NoMatchingPatternError, while the predicate
# returns false and leaves the pattern's variables nil. A survivor means no
# example feeds the match a value it rejects, so the failure mode is untested.
class Evilution::Mutator::Operator::RightwardAssignment < Evilution::Mutator::Base
  def visit_match_required_node(node)
    replace_operator(node) unless irrefutable?(node.pattern)
    super
  end

  private

  def replace_operator(node)
    location = node.operator_loc

    add_mutation(
      offset: location.start_offset,
      length: location.length,
      replacement: keyword_for(node),
      node: node
    )
  end

  # `=>` is punctuation and may touch its neighbours (`value=>Integer`), but
  # `in` is a word: written flush against them it would merge into a single
  # name. A space is added on each side that has none.
  def keyword_for(node)
    location = node.operator_loc
    before = node.value.location.end_offset == location.start_offset ? " " : ""
    after = node.pattern.location.start_offset == location.end_offset ? " " : ""

    "#{before}in#{after}"
  end

  # A bare name (`value => captured`, `value => _`) captures any value, so the
  # match can never raise and the predicate form would behave the same.
  def irrefutable?(pattern)
    pattern.is_a?(Prism::LocalVariableTargetNode)
  end
end
