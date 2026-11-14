# frozen_string_literal: true

require_relative "../result"
require_relative "coverage_gap_grouper"
require_relative "subject_scorer"
require_relative "baseline_neutralization"
require_relative "run_timings"
require_relative "mutation_timings"

class Evilution::Result::Summary
  attr_reader :results, :duration, :skipped, :skipped_sites, :disabled_mutations, :unresolved_target_files,
              :target_file_count, :infra_retried, :uncovered_code, :baseline_failures, :timings

  # skipped: every mutation left out during generation (ignore_patterns,
  # skip_sites, disable comments, Sorbet sigs); skipped_sites: the share of
  # each skip_sites preset, e.g. { logging: 3 }.
  def initialize(results:, duration: 0.0, truncated: false, skipped: 0, skipped_sites: {}, disabled_mutations: [],
                 unresolved_target_files: [], target_file_count: nil, infra_retried: 0, uncovered_code: [],
                 baseline_failures: [], timings: Evilution::Result::RunTimings.new)
    @results = results
    @duration = duration
    @truncated = truncated
    @skipped = skipped
    @skipped_sites = skipped_sites.dup.freeze
    @disabled_mutations = disabled_mutations
    @unresolved_target_files = unresolved_target_files.freeze
    @target_file_count = target_file_count
    @infra_retried = infra_retried
    @uncovered_code = uncovered_code.freeze
    @baseline_failures = baseline_failures.freeze
    @timings = timings
    freeze
  end

  # Each mutation phase summed over the mutations that measured it, in
  # seconds of process time: in a parallel run they add up across workers.
  def mutation_timing_totals
    totals = Evilution::Result::MutationTimings::PHASES.to_h { |phase| [phase, 0.0] }
    results.each do |result|
      timings = result.timings
      next unless timings

      timings.to_h.each { |phase, seconds| totals[phase] += seconds }
    end
    totals
  end

  # The kills not counted because only examples already failing in the
  # baseline failed, gathered under the spec file that was red and paired with
  # why it was. They are out of the score, so a red spec file would read as
  # full marks unless the report says they are there.
  def baseline_neutralizations
    baseline_neutralized_results.group_by { |result| result.neutral_reason.detail }.map do |spec_file, results|
      Evilution::Result::BaselineNeutralization.new(
        spec_file: spec_file, count: results.length, failures: baseline_failures_for(spec_file)
      )
    end
  end

  def baseline_neutralized
    baseline_neutralized_results.length
  end

  # Neutral results gathered by the reason they were recorded, which is what the
  # report needs to say which kind of neutral a reader is looking at
  # (EV-5pob / GH #1606).
  def neutral_results_by_reason
    neutral_results.group_by(&:neutral_reason).to_a
  end

  # What each subject — each method — scored on its own. The run's score is
  # computed per file, which says nothing about a method inside it that no
  # example reaches (EV-nlx1 / GH #1605).
  def subject_scores
    Evilution::Result::SubjectScorer.new.call(results)
  end

  # The subjects the file-level score does not speak for: something survived, or
  # nothing reached them at all.
  def subjects_needing_attention
    subject_scores.reject(&:fully_verified?)
  end

  # The same subjects, gathered under the file they live in, which is how the
  # report lists them.
  def subjects_needing_attention_by_file
    subjects_needing_attention.group_by(&:file_path).values
  end

  # Files evilution was pointed at that resolved to no test file, so nothing
  # about them was ever measured (EV-p4sm / GH #1603).
  def unresolved_targets?
    !unresolved_target_files.empty?
  end

  # Targeted lines that hold code outside every subject, so no mutation was
  # ever generated for them: `{ file:, lines: ["2-4", "9"] }` per file.
  def uncovered_code?
    !uncovered_code.empty?
  end

  def truncated?
    @truncated
  end

  def total
    results.length
  end

  def killed
    results.count(&:killed?)
  end

  def survived
    results.count(&:survived?)
  end

  def timed_out
    results.count(&:timeout?)
  end

  def errors
    results.count(&:error?)
  end

  def neutral
    results.count(&:neutral?)
  end

  def equivalent
    results.count(&:equivalent?)
  end

  def unresolved
    results.count(&:unresolved?)
  end

  def unparseable
    results.count(&:unparseable?)
  end

  def uncovered
    results.count(&:uncovered?)
  end

  # An uncovered mutation stays in: it is untested code, scored as the
  # survivor running it would have produced.
  def score_denominator
    total - errors - neutral - equivalent - unresolved - unparseable
  end

  def score
    denominator = score_denominator
    return 0.0 if denominator.zero?

    killed.to_f / denominator
  end

  # A target file that was never tested fails the run on its own: the score
  # only speaks for the files that did resolve to a spec.
  def success?(min_score: 1.0)
    return false if unresolved_targets?

    score >= min_score
  end

  def survived_results
    results.select(&:survived?)
  end

  def killed_results
    results.select(&:killed?)
  end

  def neutral_results
    results.select(&:neutral?)
  end

  def equivalent_results
    results.select(&:equivalent?)
  end

  def unresolved_results
    results.select(&:unresolved?)
  end

  def unparseable_results
    results.select(&:unparseable?)
  end

  def uncovered_results
    results.select(&:uncovered?)
  end

  def coverage_gaps
    Evilution::Result::CoverageGapGrouper.new.call(survived_results)
  end

  def killtime
    results.sum(0.0, &:duration)
  end

  def efficiency
    return 0.0 if duration.zero?

    killtime / duration
  end

  def mutations_per_second
    return 0.0 if duration.zero?

    total.to_f / duration
  end

  def peak_memory_mb
    max_rss = results.filter_map(&:child_rss_kb).max
    max_rss && (max_rss / 1024.0)
  end

  private

  def baseline_neutralized_results
    neutral_results.select { |result| result.neutral_reason && result.neutral_reason.kind == :baseline_failure }
  end

  # No spec file named means the run was given its spec files explicitly, and
  # any of them being red neutralizes the survivor.
  def baseline_failures_for(spec_file)
    return baseline_failures if spec_file.nil?

    baseline_failures.select { |failure| failure.spec_file == spec_file }
  end
end
