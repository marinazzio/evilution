# frozen_string_literal: true

require "json"
require "time"
require_relative "suggestion"

require_relative "../reporter"

class Evilution::Reporter::JSON
  def initialize(suggest_tests: false, integration: :rspec)
    @suggestion = Evilution::Reporter::Suggestion.new(suggest_tests: suggest_tests, integration: integration)
  end

  def call(summary)
    ::JSON.generate(build_report(summary))
  end

  private

  # rubocop:disable Metrics/PerceivedComplexity
  def build_report(summary)
    report = {
      version: Evilution::VERSION,
      timestamp: Time.now.iso8601,
      summary: build_summary(summary),
      survived: summary.survived_results.map { |r| build_mutation_detail(r) },
      coverage_gaps: build_coverage_gaps(summary),
      killed: summary.killed_results.map { |r| build_mutation_detail(r) },
      neutral: summary.neutral_results.map { |r| build_mutation_detail(r) },
      timed_out: summary.results.select(&:timeout?).map { |r| build_mutation_detail(r) },
      errors: summary.results.select(&:error?).map { |r| build_mutation_detail(r) },
      equivalent: summary.equivalent_results.map { |r| build_mutation_detail(r) }
    }
    append_disabled_to_report(report, summary)
    report
  end
  # rubocop:enable Metrics/PerceivedComplexity

  def append_disabled_to_report(report, summary)
    return unless summary.disabled_mutations.any?

    report[:disabled] = summary.disabled_mutations.map { |m| build_disabled_detail(m) }
  end

  def build_summary(summary)
    data = {
      total: summary.total,
      killed: summary.killed,
      survived: summary.survived,
      timed_out: summary.timed_out,
      errors: summary.errors,
      neutral: summary.neutral,
      equivalent: summary.equivalent,
      score: summary.score.round(4),
      duration: summary.duration.round(4),
      killtime: summary.killtime.round(4),
      efficiency: summary.efficiency.round(4),
      mutations_per_second: summary.mutations_per_second.round(2)
    }
    data[:truncated] = true if summary.truncated?
    data[:skipped] = summary.skipped if summary.skipped.positive?
    peak = summary.peak_memory_mb
    data[:peak_memory_mb] = peak.round(1) if peak
    data
  end

  def build_mutation_detail(result)
    mutation = result.mutation
    detail = {
      operator: mutation.operator_name,
      file: mutation.file_path,
      line: mutation.line,
      status: result.status.to_s,
      duration: result.duration.round(4),
      diff: mutation.diff
    }
    detail[:suggestion] = @suggestion.suggestion_for(mutation) if result.status == :survived
    detail[:test_command] = result.test_command if result.test_command
    detail[:parent_rss_kb] = result.parent_rss_kb if result.parent_rss_kb
    detail[:child_rss_kb] = result.child_rss_kb if result.child_rss_kb
    detail[:memory_delta_kb] = result.memory_delta_kb if result.memory_delta_kb
    detail[:error_message] = result.error_message if result.error_message
    detail
  end

  def build_coverage_gaps(summary)
    summary.coverage_gaps.map do |gap|
      {
        file: gap.file_path,
        subject: gap.subject_name,
        line: gap.line,
        operators: gap.operator_names,
        count: gap.count,
        mutations: gap.mutation_results.map { |r| build_mutation_detail(r) }
      }
    end
  end

  def build_disabled_detail(mutation)
    {
      operator: mutation.operator_name,
      file: mutation.file_path,
      line: mutation.line,
      diff: mutation.diff
    }
  end
end
