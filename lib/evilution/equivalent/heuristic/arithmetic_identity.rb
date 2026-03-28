# frozen_string_literal: true

require_relative "../heuristic"

class Evilution::Equivalent::Heuristic::ArithmeticIdentity
  # Patterns where the original expression is an arithmetic identity operation.
  # "x + 0" is identity (equals x), so mutating the 0 to something else means
  # the original was a no-op — if the test doesn't catch it, it's likely equivalent.
  ADDITIVE_IDENTITY = /[\w)\].]+\s*[+-]\s*0\b|\b0\s*\+\s*[\w(\[]/
  MULTIPLICATIVE_IDENTITY = %r{[\w)\].]+\s*[*/]\s*1\b|\b1\s*\*\s*[\w(\[]}
  EXPONENT_IDENTITY = /[\w)\].]+\s*\*\*\s*1\b/

  def match?(mutation)
    return false unless mutation.operator_name == "integer_literal"

    removed = diff_line(mutation.diff, "- ")
    return false unless removed

    content = removed.sub(/^- /, "")
    content.match?(ADDITIVE_IDENTITY) ||
      content.match?(MULTIPLICATIVE_IDENTITY) ||
      content.match?(EXPONENT_IDENTITY)
  end

  private

  def diff_line(diff, prefix)
    diff.split("\n").find { |l| l.start_with?(prefix) }
  end
end
