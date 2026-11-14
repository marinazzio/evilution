# frozen_string_literal: true

require_relative "../heuristic"

class Evilution::Equivalent::Heuristic::CommentMarking
  MARKER = /#\s*evilution:equivalent\b/

  def match?(mutation)
    source = mutation.original_source
    return false unless source && marked?(source)

    lines = source.lines
    line_index = mutation.line - 1
    return false if line_index.negative? || line_index >= lines.length

    return true if lines[line_index].match?(MARKER)
    return true if line_index.positive? && lines[line_index - 1].match?(MARKER)

    false
  end

  private

  # Whether the marker is anywhere in the file: when it is not, no line of
  # it is looked at, sparing the split of the file into lines per mutation.
  # Mutations come file by file, so the answer for the last file is kept. A
  # marker found here may still run across a line break; the lines decide.
  def marked?(source)
    return @marked if @source.equal?(source)

    @source = source
    @marked = source.match?(MARKER)
  end
end
