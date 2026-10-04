# frozen_string_literal: true

require_relative "../operator"
require_relative "../../ast/regexp_pattern"

# Swap a regexp quantifier between "zero or more" and "one or more": `*`
# becomes `+` and `+` becomes `*`, keeping a lazy (`*?`) or possessive (`*+`)
# quantifier lazy or possessive.
#
# Only the empty case changes: `/\A\d*\z/` accepts "" and `/\A\d+\z/` does
# not. A survivor means no example checks how the pattern treats an absent
# repetition. RegexSimplification's quantifier removal changes the many case
# too; this isolates the empty one.
#
# Making a recursive `\g<name>` call mandatory can make the pattern recurse
# forever, so each mutant is compiled first and dropped if it does not.
class Evilution::Mutator::Operator::RegexpQuantifierMinimumSwap < Evilution::Mutator::Base
  SWAPS = {
    zero_or_more: "+", zero_or_more_reluctant: "+?", zero_or_more_possessive: "++",
    one_or_more: "*", one_or_more_reluctant: "*?", one_or_more_possessive: "*+"
  }.freeze

  def visit_regular_expression_node(node)
    pattern = Evilution::AST::RegexpPattern.parse(node)
    pattern.tokens.each { |token| swap(node, pattern, token) } if pattern
    super
  end

  private

  def swap(node, pattern, token)
    return unless token.type == :quantifier

    replacement = SWAPS[token.token]
    return if replacement.nil?
    return unless pattern.compiles?(token.start_offset, token.end_offset, replacement)

    add_mutation(
      offset: token.start_offset,
      length: token.end_offset - token.start_offset,
      replacement: replacement,
      node: node
    )
  end
end
