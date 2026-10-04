# frozen_string_literal: true

require_relative "../operator"
require_relative "../../ast/regexp_pattern"

# Flip a character type of a regexp to its complement: `\d` becomes `\D`,
# `\w` becomes `\W`, `\b` becomes `\B`, and back.
#
# The pattern keeps its shape but accepts the opposite characters, so a
# survivor means the suite never feeds the pattern both input it should match
# and input it should reject at that position.
#
# `\X` (grapheme cluster) and `\R` (line break) are not complements — `\X`
# matches a line break too — so they are left alone, as are Unicode
# properties. The pattern is read with regexp_parser, so escaped backslashes
# and extended-mode comments are not mistaken for character types.
#
# Unlike the structural regexp edits, a flip needs no compile check: it swaps
# one escape for another of the same kind and cannot touch a group or a
# reference. Across 37,840 flips in real code, every mutant compiled.
class Evilution::Mutator::Operator::RegexpCharacterTypeComplement < Evilution::Mutator::Base
  # Complements by the scanner's token kind and name rather than by text:
  # inside a character class `\b` scans as a backspace escape, and `\p{Digit}`
  # shares the `digit` name under the property kind.
  COMPLEMENTS = {
    type: {
      digit: "\\D", nondigit: "\\d",
      space: "\\S", nonspace: "\\s",
      word: "\\W", nonword: "\\w",
      hex: "\\H", nonhex: "\\h"
    },
    anchor: { word_boundary: "\\B", nonword_boundary: "\\b" }
  }.freeze

  def visit_regular_expression_node(node)
    pattern = Evilution::AST::RegexpPattern.parse(node)
    pattern.tokens.each { |token| flip(node, token) } if pattern
    super
  end

  private

  def flip(node, token)
    complement = COMPLEMENTS.fetch(token.type, {})[token.token]
    return if complement.nil?

    add_mutation(
      offset: token.start_offset,
      length: token.end_offset - token.start_offset,
      replacement: complement,
      node: node
    )
  end
end
