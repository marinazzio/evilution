# frozen_string_literal: true

require_relative "../coverage"
require_relative "map"

# Wraps each example with a before/after coverage diff and attributes the
# newly-executed lines (in target files only) to that example's location.
# coverage_source is injected for testability; in production it is
# -> { ::Coverage.peek_result }.
class Evilution::Coverage::Recorder
  # prior_counts: line counts taken before the build forked. Ruby starts a
  # forked child's counts at zero, so the lines a file ran while it loaded in
  # the parent (a preload) are known only from these.
  def initialize(target_files:, coverage_source: -> { ::Coverage.peek_result }, prior_counts: {})
    @target_files = target_files.to_a
    @coverage_source = coverage_source
    @prior_counts = prior_counts
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

  # vouched_files: the target files whose coverage the build can stand behind
  # (see MapBuilder). For those, the end of the build is read once more: what
  # ran after the last example counts as executed, and the executable lines
  # still at zero are recorded as never run.
  def to_map(built_files:, vouched_files: [], spec_files: [])
    record_prior
    missed = record_end_of_build(vouched_files)
    Evilution::Coverage::Map.new(
      index: materialize(@index),
      built_files: built_files,
      executed_lines: @executed.transform_values(&:uniq),
      missed_lines: missed,
      spec_files: spec_files
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

  def record_prior
    @target_files.each do |file|
      counts = line_counts(@prior_counts[file])
      record_executed(file, counts) if counts
    end
  end

  def record_end_of_build(files)
    final = snapshot
    files.each_with_object({}) do |file, missed|
      counts = line_counts(final[file])
      next unless counts

      record_executed(file, counts)
      missed[file] = unexecuted_lines(counts)
    end
  end

  # nil marks a line that is not executable; zero, one that never ran in the
  # build's child. A line that ran before the fork is in the executed lines,
  # which Map#uncovered? lets win.
  def unexecuted_lines(counts)
    counts.each_with_index.filter_map { |count, idx| idx + 1 if count.is_a?(Integer) && count.zero? }
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
