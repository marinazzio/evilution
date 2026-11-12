# frozen_string_literal: true

require_relative "../runner"

# Keeps the mutations that change a line of the range asked for in their
# file. Subjects are selected when they overlap a range, but a subject can
# carry mutations of lines outside it -- class-body code is attributed to the
# scope's first method, a constant's subject spans its whole block -- and
# those are not what was asked for.
#
# A mutation is kept when any line it changes falls in the range, so one that
# starts above the range and reaches into it still counts. Files without a
# range keep every mutation.
class Evilution::Runner::LineRangeFilter
  def initialize(line_ranges)
    @line_ranges = line_ranges
  end

  def call(mutations)
    return mutations if @line_ranges.empty?

    mutations.select { |mutation| in_range?(mutation) }
  end

  private

  def in_range?(mutation)
    range = @line_ranges[mutation.file_path]
    return true unless range

    lines = mutation.changed_lines
    lines.first <= range.last && lines.last >= range.first
  end
end
