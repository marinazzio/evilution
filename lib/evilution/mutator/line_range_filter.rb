# frozen_string_literal: true

require_relative "../mutator"

# Whether a mutation changes a line of the range asked for in its file.
# Subjects are selected when they overlap a range, but a subject can carry
# mutations of lines outside it -- class-body code is attributed to the
# scope's first method, a constant's subject spans its whole block -- and
# those are not what was asked for.
#
# A mutation is covered when any line it changes falls in the range, so one
# that starts above the range and reaches into it still counts. Files without
# a range cover every mutation.
class Evilution::Mutator::LineRangeFilter
  def initialize(line_ranges)
    @line_ranges = line_ranges
  end

  def cover?(file_path, lines)
    range = @line_ranges[file_path]
    return true unless range

    lines.first <= range.last && lines.last >= range.first
  end
end
