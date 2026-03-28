# frozen_string_literal: true

require_relative "../heuristic"

class Evilution::Equivalent::Heuristic::CommentMarking
  MARKER = /#\s*evilution:equivalent\b/

  def match?(mutation)
    source = mutation.original_source
    return false unless source

    lines = source.lines
    line_index = mutation.line - 1
    return false if line_index.negative? || line_index >= lines.length

    return true if lines[line_index].match?(MARKER)
    return true if line_index.positive? && lines[line_index - 1].match?(MARKER)

    false
  end
end
