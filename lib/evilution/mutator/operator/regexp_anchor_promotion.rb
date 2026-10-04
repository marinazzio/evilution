# frozen_string_literal: true

require_relative "../operator"
require_relative "../../ast/regexp_pattern"

# Promote a line anchor to the matching string anchor: `^` becomes `\A`, `$`
# becomes `\z`, and `\Z`, which still allows a trailing newline, becomes `\z`.
#
# A line anchor also matches around every newline in the input, so `/^admin$/`
# accepts "evil\nadmin" while `/\Aadmin\z/` does not — the classic multiline
# injection gap. A survivor means no example feeds the pattern multi-line
# input, or the anchor should have been a string anchor all along.
#
# Unlike RegexSimplification, which removes anchors, this keeps the pattern
# anchored and only narrows what the anchor accepts. The pattern is read with
# regexp_parser, so `^` and `$` inside a character class, escaped, or in an
# extended-mode comment are left alone. Swapping one anchor for another cannot
# touch a group or a reference, so no compile check is needed.
class Evilution::Mutator::Operator::RegexpAnchorPromotion < Evilution::Mutator::Base
  PROMOTIONS = { bol: "\\A", eol: "\\z", eos_ob_eol: "\\z" }.freeze

  def visit_regular_expression_node(node)
    pattern = Evilution::AST::RegexpPattern.parse(node)
    pattern.tokens.each { |token| promote(node, token) } if pattern
    super
  end

  private

  def promote(node, token)
    return unless token.type == :anchor

    promotion = PROMOTIONS[token.token]
    return if promotion.nil?

    add_mutation(
      offset: token.start_offset,
      length: token.end_offset - token.start_offset,
      replacement: promotion,
      node: node
    )
  end
end
