# frozen_string_literal: true

require_relative "../operator"

# Rewrite a match against an anchored literal regexp into a prefix or suffix
# predicate: `line =~ /^foo/` becomes `line.start_with?("foo")`, and
# `line.match?(/bar$/)` becomes `line.end_with?("bar")`. Handles `=~`,
# `match` and `match?`, with the regexp on either side.
#
# Line anchors carry the signal: `^` also matches after any newline, and `$`
# / `\Z` before a trailing one, where the predicates do not — a survivor
# means no test feeds multi-line input, or the anchor should have been `\A` /
# `\z`. With the string anchors `\A` / `\z` the truth value is identical, so
# only `=~` and `match` are rewritten there (their return value — an index
# or MatchData — still differs from a boolean); `match?` would be an exact
# equivalent and is skipped.
#
# Only a flag-free pattern of one anchor plus literal characters qualifies,
# and only on a call without a block: `match` yields its MatchData to one,
# which the predicate would silently drop.
class Evilution::Mutator::Operator::RegexpAnchorToPredicate < Evilution::Mutator::Base
  SELECTORS = %i[=~ match match?].freeze
  private_constant :SELECTORS

  START_ANCHORS = { "^" => :line, "\\A" => :string }.freeze
  private_constant :START_ANCHORS

  END_ANCHORS = { "$" => :line, "\\Z" => :line, "\\z" => :string }.freeze
  private_constant :END_ANCHORS

  METACHARACTERS = ".*+?()[]{}|^$".chars.to_set.freeze
  private_constant :METACHARACTERS

  # Operands that need no parentheses in front of `.start_with?`.
  SIMPLE_OPERANDS = [
    Prism::LocalVariableReadNode,
    Prism::InstanceVariableReadNode,
    Prism::ClassVariableReadNode,
    Prism::GlobalVariableReadNode,
    Prism::ConstantReadNode,
    Prism::ConstantPathNode,
    Prism::SelfNode,
    Prism::StringNode,
    Prism::ParenthesesNode
  ].freeze
  private_constant :SIMPLE_OPERANDS

  # A backslash pair or a single character. A literal cannot end in a lone
  # backslash, since that would escape its closing delimiter.
  TOKEN = /\\.|./m
  private_constant :TOKEN

  IDENTIFIER = /\A[[:alpha:]_]/
  private_constant :IDENTIFIER

  def visit_call_node(node)
    rewrite(node) if SELECTORS.include?(node.name)
    super
  end

  private

  def rewrite(node)
    return unless node.arguments in Prism::ArgumentsNode[arguments: [argument]]
    return if node.receiver.nil? || node.block

    regexp, operand = split_operands(node.receiver, argument)
    return if regexp.nil?

    predicate, literal = anchored_literal(regexp, node.name)
    return if predicate.nil?

    replacement = "#{operand_source(operand)}#{call_operator(node)}#{predicate}(#{literal.inspect})"
    replace_span(node: node, target: node, replacement: replacement)
  end

  def split_operands(receiver, argument)
    if argument.is_a?(Prism::RegularExpressionNode)
      [argument, receiver]
    elsif receiver.is_a?(Prism::RegularExpressionNode)
      [receiver, argument]
    end
  end

  # [predicate, literal] when the pattern is one anchor plus literal
  # characters and the rewrite is not an exact equivalent; nil otherwise.
  def anchored_literal(regexp, selector)
    return if regexp.closing_loc.length > 1

    predicate, kind, body = split_anchor(regexp.content.scan(TOKEN))
    return if predicate.nil? || (kind == :string && selector == :match?)

    literal = literal_text(body)
    [predicate, literal] if literal && !literal.empty?
  end

  # A pattern anchored at both ends needs no check here: the other anchor
  # (`\z`, `\Z`, `$`, `^`, `\A`) is never a literal character, so
  # literal_text rejects the body.
  def split_anchor(tokens)
    if (start_kind = START_ANCHORS[tokens.first])
      [:start_with?, start_kind, tokens.drop(1)]
    elsif (end_kind = END_ANCHORS[tokens.last])
      [:end_with?, end_kind, tokens[...-1]]
    end
  end

  def literal_text(tokens)
    chars = tokens.map { |token| literal_char(token) }
    chars.join if chars.all?
  end

  def literal_char(token)
    if token.start_with?("\\")
      escaped = token[1]
      escaped unless escaped.match?(/[[:alnum:]]/)
    elsif !METACHARACTERS.include?(token)
      token
    end
  end

  def operand_source(operand)
    source = source_of(operand)
    simple_operand?(operand) ? source : "(#{source})"
  end

  def simple_operand?(operand)
    return true if SIMPLE_OPERANDS.any? { |type| operand.is_a?(type) }

    operand.is_a?(Prism::CallNode) && (operand.name.match?(IDENTIFIER) || operand.name == :[])
  end

  def call_operator(node)
    node.call_operator_loc ? node.call_operator_loc.slice : "."
  end
end
