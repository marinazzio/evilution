# frozen_string_literal: true

require_relative "../heuristic"

class Evilution::Equivalent::Heuristic::FrozenString
  FREEZE_PATTERN = /\.freeze\b/

  def match?(mutation)
    return false unless mutation.operator_name == "string_literal"

    diff = mutation.diff
    removed = diff_line(diff, "- ")
    added = diff_line(diff, "+ ")
    return false unless removed && added

    removed.match?(FREEZE_PATTERN) && added.match?(FREEZE_PATTERN)
  end

  private

  def diff_line(diff, prefix)
    diff.split("\n").find { |l| l.start_with?(prefix) }
  end
end
