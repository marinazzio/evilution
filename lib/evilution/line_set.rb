# frozen_string_literal: true

require_relative "version"

# The lines of a file a run is limited to, as any number of line ranges: the
# one range given on the command line (lib/foo.rb:15-30), or each hunk git
# reports as changed. Ranges are kept sorted, with overlapping and touching
# ones merged; an open-ended range ends in Float::INFINITY.
class Evilution::LineSet
  attr_reader :ranges

  def self.wrap(lines)
    lines.is_a?(self) ? lines : new([lines])
  end

  def initialize(ranges)
    @ranges = merge(ranges.reject { |range| range.last < range.first }).freeze
    freeze
  end

  def cover?(line)
    ranges.any? { |range| range.cover?(line) }
  end

  # Whether any line from first to last is in the set.
  def overlap?(first, last)
    ranges.any? { |range| first <= range.last && last >= range.first }
  end

  def &(other)
    pairs = ranges.product(self.class.wrap(other).ranges)
    self.class.new(pairs.map { |mine, theirs| [mine.first, theirs.first].max..[mine.last, theirs.last].min })
  end

  def empty?
    ranges.empty?
  end

  def ==(other)
    other.is_a?(self.class) && ranges == other.ranges
  end
  alias eql? ==

  def hash
    ranges.hash
  end

  # Spelled the way a range is passed on the command line: `2-4,9`, `3-`.
  def to_s
    ranges.map { |range| label(range) }.join(",")
  end

  private

  def merge(ranges)
    ranges.sort_by(&:first).each_with_object([]) do |range, merged|
      last = merged.last
      if last && range.first <= last.last + 1
        merged[-1] = last.first..[last.last, range.last].max
      else
        merged << range
      end
    end
  end

  def label(range)
    return "#{range.first}-" if range.last == Float::INFINITY
    return range.first.to_s if range.first == range.last

    "#{range.first}-#{range.last}"
  end
end
