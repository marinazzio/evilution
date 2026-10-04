# frozen_string_literal: true

require_relative "../operator"
require_relative "../../ast/regexp_pattern"

# Simplify a regexp literal one piece at a time: remove a quantifier
# (`/a+/` -> `/a/`), remove an anchor (`/^a$/` -> `/a$/`), or drop the dash of
# a character-class range (`/[a-z]/` -> `/[az]/`).
#
# The pattern is read with regexp_parser, so only real quantifiers, anchors and
# ranges are touched: the `?` of a group opener (`(?:`, `(?<name>`, `(?=`), the
# inside of a `(?#...)` comment, a property's negation (`\p{^Alpha}`) and the
# comments of an extended pattern contain the same characters without being
# any of them. Each edit is made in place in the source and kept only if the
# pattern still compiles.
class Evilution::Mutator::Operator::RegexSimplification < Evilution::Mutator::Base
  # Line and string anchors. Word boundaries and `\G` are assertions of a
  # different kind and are left alone.
  REMOVABLE_ANCHORS = %i[bol eol bos eos eos_ob_eol].freeze

  def visit_regular_expression_node(node)
    pattern = Evilution::AST::RegexpPattern.parse(node)
    if pattern
      remove_quantifiers(node, pattern)
      remove_anchors(node, pattern)
      remove_class_ranges(node, pattern)
    end

    super
  end

  private

  def remove_quantifiers(node, pattern)
    quantifier_spans(pattern.tokens).each do |start_offset, end_offset|
      remove_span(node, pattern, start_offset, end_offset)
    end
  end

  # Ruby reads `{2,}?` as one lazy interval, while regexp_parser reports an
  # interval followed by a `?` quantifier. The two are joined so the lazy
  # marker is removed with its interval instead of becoming a quantifier of
  # its own.
  def quantifier_spans(tokens)
    quantifiers = tokens.select { |token| token.type == :quantifier }
    spans = []
    quantifiers.each do |token|
      previous = spans.last
      if lazy_marker_of?(token, previous)
        previous[1] = token.end_offset
      else
        spans << [token.start_offset, token.end_offset, token]
      end
    end
    spans.map { |start_offset, end_offset, _token| [start_offset, end_offset] }
  end

  def lazy_marker_of?(token, previous)
    return false if previous.nil?

    previous.last.text.start_with?("{") && token.text == "?" && previous[1] == token.start_offset
  end

  def remove_anchors(node, pattern)
    pattern.tokens.each do |token|
      next unless token.type == :anchor && REMOVABLE_ANCHORS.include?(token.token)

      remove_span(node, pattern, token.start_offset, token.end_offset)
    end
  end

  def remove_class_ranges(node, pattern)
    pattern.tokens.each do |token|
      next unless token.type == :set && token.token == :range

      remove_span(node, pattern, token.start_offset, token.end_offset)
    end
  end

  def remove_span(node, pattern, start_offset, end_offset)
    return unless pattern.compiles?(start_offset, end_offset, "")

    add_mutation(offset: start_offset, length: end_offset - start_offset, replacement: "", node: node)
  end
end
