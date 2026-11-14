# frozen_string_literal: true

require "diff/lcs"
# Loaded by mutation.rb, once Evilution::Mutation is defined.

# The lines a mutation takes out of its file and puts in, as "- line" and
# "+ line", in the order Diff::LCS.diff lists them for the two whole files.
#
# A mutation changes a few lines of a file that can run to thousands, and
# splitting both into lines to diff them costs per mutation what the file
# is long. Diff::LCS first sets aside the longest run of equal lines at the
# top of the two sequences and then the longest at the bottom; what it
# reports comes from the lines between the two runs. So only those lines
# are split and handed to it, found from where the bytes of the two sources
# stop being equal, and with them the first equal line after them: the
# lines left unmatched before it are reported in the order a match puts
# them in, which differs from the order at the end of a sequence.
module Evilution::Mutation::LineDiff
  NEWLINE = "\n"
  private_constant :NEWLINE

  Window = Data.define(:start, :original_end, :mutated_end)
  private_constant :Window

  def self.call(original, mutated)
    return "" if original == mutated

    window = window(original.b, mutated.b)
    changes = ::Diff::LCS.diff(lines(original, window.start, window.original_end),
                               lines(mutated, window.start, window.mutated_end))
    changes.flatten(1).map { |change| "#{change.action} #{change.element.chomp}" }.join(NEWLINE)
  end

  # The lines of the source between two byte offsets, in its encoding.
  def self.lines(source, from, to)
    source.byteslice(from, to - from).lines
  end

  # The bytes from the start of the first line that differs to the end of
  # the first equal line after it, in each source. Both are binary.
  def self.window(original, mutated)
    start = line_start_before(original, common_prefix(original, mutated))
    original_rest = original.byteslice(start, original.bytesize - start)
    mutated_rest = mutated.byteslice(start, mutated.bytesize - start)
    tail = first_equal_line(original_rest, mutated_rest)
    growth = mutated_rest.bytesize - original_rest.bytesize
    Window.new(start: start, original_end: start + tail, mutated_end: start + tail + growth)
  end

  # Where the first equal line after the change ends in the original, from
  # the start of the first line that differs; the end of the source when
  # the two differ down to their last line.
  def self.first_equal_line(original, mutated)
    suffix = common_suffix(original, mutated)
    from = suffix_line_start(original, mutated, suffix)
    return original.bytesize unless from

    line_end = original.index(NEWLINE, from)
    line_end ? line_end + 1 : original.bytesize
  end

  # The first offset in the original's equal tail that starts a line in
  # both sources, or nil when none does. Past a line break inside the tail
  # a line starts in both; where the tail itself starts, only when both
  # break a line there.
  def self.suffix_line_start(original, mutated, suffix)
    from = original.bytesize - suffix
    return from if line_start?(original, from) && line_start?(mutated, mutated.bytesize - suffix)

    line_break = original.index(NEWLINE, from)
    line_break && (line_break + 1)
  end

  def self.line_start?(source, offset)
    offset.zero? || source.getbyte(offset - 1) == NEWLINE.ord
  end

  def self.line_start_before(source, offset)
    return 0 if offset.zero?

    line_break = source.rindex(NEWLINE, offset - 1)
    line_break ? line_break + 1 : 0
  end

  # How many bytes the two start with alike, found by halving: each probe
  # compares two shared slices in C rather than walking the bytes in Ruby.
  def self.common_prefix(left, right)
    longest_equal(left, right) { |source, length| source.byteslice(0, length) }
  end

  def self.common_suffix(left, right)
    longest_equal(left, right) { |source, length| source.byteslice(source.bytesize - length, length) }
  end

  def self.longest_equal(left, right)
    low = 0
    high = [left.bytesize, right.bytesize].min
    while low < high
      probe = (low + high + 1) / 2
      if yield(left, probe) == yield(right, probe)
        low = probe
      else
        high = probe - 1
      end
    end
    low
  end

  private_class_method :lines, :window, :first_equal_line, :suffix_line_start, :line_start?,
                       :line_start_before, :common_prefix, :common_suffix, :longest_equal
end
