# frozen_string_literal: true

require_relative "../coverage"
require_relative "map"

# Wraps each example with a before/after coverage diff and attributes the
# newly-executed lines (in target files only) to that example's location.
# coverage_source is injected for testability; in production it is
# -> { ::Coverage.peek_result }.
class Evilution::Coverage::Recorder
  def initialize(target_files:, coverage_source: -> { ::Coverage.peek_result })
    @target_files = target_files.to_a
    @coverage_source = coverage_source
    @index = Hash.new { |h, file| h[file] = Hash.new { |g, line| g[line] = [] } }
    @executed = Hash.new { |h, file| h[file] = [] }
  end

  def around_example(example_location)
    before = snapshot
    result = yield
    after = snapshot
    attribute(before, after, example_location)
    result
  end

  def to_map(built_files:)
    Evilution::Coverage::Map.new(
      index: materialize(@index),
      built_files: built_files,
      executed_lines: @executed.transform_values(&:uniq)
    )
  end

  private

  def snapshot
    @coverage_source.call || {}
  end

  def attribute(before, after, example_location)
    @target_files.each do |file|
      after_counts = line_counts(after[file])
      next unless after_counts

      record_executed(file, after_counts)
      record_increases(file, line_counts(before[file]) || [], after_counts, example_location)
    end
  end

  # Every line with a non-zero count in the after-snapshot has run at least once
  # by now -- including lines covered only at load (a `def` line is already > 0
  # in the first example's after-snapshot). Recording them lets the Map tell a
  # load-covered line from a line that never ran.
  def record_executed(file, after_counts)
    after_counts.each_with_index do |count, idx|
      next if count.nil? || count.zero?

      @executed[file] << (idx + 1)
    end
  end

  # Credit example_location with every line whose execution count rose between
  # the before/after snapshots (a newly-executed, executable line).
  def record_increases(file, before_counts, after_counts, example_location)
    after_counts.each_with_index do |count, idx|
      next if count.nil? || count.zero?
      next unless count > (before_counts[idx] || 0)

      @index[file][idx + 1] << example_location
    end
  end

  # Coverage.peek_result yields per-file line counts either as a bare array
  # (legacy Coverage.start) or as a { lines: [...] } hash (Coverage.start with
  # lines:/branches:/methods: modes). Normalize to the bare counts array.
  def line_counts(entry)
    entry.is_a?(Hash) ? entry[:lines] : entry
  end

  def materialize(index)
    index.each_with_object({}) do |(file, lines), out|
      out[file] = lines.each_with_object({}) { |(line, locs), inner| inner[line] = locs }
    end
  end
end
