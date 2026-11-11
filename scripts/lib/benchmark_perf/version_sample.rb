# frozen_string_literal: true

require_relative "run_result"

module BenchmarkPerf
  def self.median(values)
    return nil if values.empty?

    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end

  # All repeats of one version on one target.
  class VersionSample
    attr_reader :ok_runs, :statuses, :unstable_count, :operators

    def initialize(runs:)
      @runs = runs
      @ok_runs = runs.reject(&:failed?)
      @statuses = majority_statuses
      @unstable_count = count_unstable
      @operators = median_operators
      freeze
    end

    def failed_count
      @runs.size - ok_runs.size
    end

    def failed?
      ok_runs.empty?
    end

    def errors
      @runs.select(&:failed?).map(&:error)
    end

    def wall_median
      BenchmarkPerf.median(ok_runs.map(&:wall))
    end

    def wall_min
      ok_runs.map(&:wall).min
    end

    def wall_max
      ok_runs.map(&:wall).max
    end

    def duration_median
      BenchmarkPerf.median(ok_runs.map(&:duration))
    end

    def killtime_median
      BenchmarkPerf.median(ok_runs.map(&:killtime))
    end

    def mutant_count
      statuses.size
    end

    def status_counts
      statuses.values.tally
    end

    def phases
      failed? ? nil : ok_runs.first.phases
    end

    private

    def all_keys
      ok_runs.flat_map { |run| run.statuses.keys }.uniq
    end

    def majority_statuses
      all_keys.to_h { |key| [key, majority(ok_runs.filter_map { |run| run.statuses[key] })] }.freeze
    end

    # Ties lean towards "not killed" so a flaky kill never hides a lost one.
    def majority(observed)
      tally = observed.tally
      top = tally.values.max
      tied = tally.select { |_, count| count == top }.keys
      tied -= ["killed"] if tied.size > 1
      tied.min_by { |status| STATUSES.index(status) || STATUSES.size }
    end

    def count_unstable
      all_keys.count { |key| ok_runs.filter_map { |run| run.statuses[key] }.uniq.size > 1 }
    end

    def median_operators
      return {}.freeze if failed?

      ok_runs.first.operators.to_h do |operator, entry|
        durations = ok_runs.filter_map { |run| run.operators.dig(operator, :duration) }
        [operator, { count: entry[:count], duration: BenchmarkPerf.median(durations) }]
      end.freeze
    end
  end
end
