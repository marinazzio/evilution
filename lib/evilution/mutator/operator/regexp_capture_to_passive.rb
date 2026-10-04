# frozen_string_literal: true

require_relative "../operator"
require_relative "../../ast/regexp_pattern"

# Turn a regexp capture group into a passive group: `/id=(\d+)/` becomes
# `/id=(?:\d+)/`.
#
# The pattern matches the same text but no longer captures, so `$1`, `m[1]`,
# a `scan` result or a `\1` in a replacement loses its value. A survivor means
# nothing downstream reads the capture.
#
# Only mutants that can change something are emitted:
# - a regexp passed straight to `match?` or `!~` never exposes its captures;
# - with a named group present Ruby keeps only named captures, so a plain
#   group captures nothing to begin with;
# - a numbered reference inside the pattern (`\2`, `\k<1>`, `\g<1>`) would be
#   renumbered by the passive group and quietly point elsewhere, which tests
#   the pattern rather than whether the capture is used.
#
# With named groups and numbered references ruled out, nothing else in the
# pattern can refer to a plain group, so turning it passive always compiles
# and needs no check.
class Evilution::Mutator::Operator::RegexpCaptureToPassive < Evilution::Mutator::Base
  CAPTURE_FREE_CALLS = %i[match? !~].freeze
  NAMED_GROUP_TOKENS = %i[named_ab named_sq].freeze

  def initialize(**options)
    super
    @capture_free = Set.new.compare_by_identity
  end

  def visit_call_node(node)
    if CAPTURE_FREE_CALLS.include?(node.name)
      @capture_free << node.receiver
      @capture_free.merge(node.arguments.arguments) if node.arguments
    end
    super
  end

  def visit_regular_expression_node(node)
    pattern = Evilution::AST::RegexpPattern.parse(node) unless @capture_free.include?(node)
    pattern.tokens.each { |token| make_passive(node, token) } if pattern && plain_captures_matter?(pattern)
    super
  end

  private

  def plain_captures_matter?(pattern)
    pattern.tokens.none? do |token|
      (token.type == :group && NAMED_GROUP_TOKENS.include?(token.token)) ||
        (token.type == :backref && token.token.to_s.start_with?("number"))
    end
  end

  def make_passive(node, token)
    return unless token.type == :group && token.token == :capture

    add_mutation(offset: token.start_offset, length: token.end_offset - token.start_offset, replacement: "(?:", node: node)
  end
end
