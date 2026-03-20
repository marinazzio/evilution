# frozen_string_literal: true

require "json"
require "time"
require_relative "suggestion"

module Evilution
  module Reporter
    class JSON
      def initialize
        @suggestion = Suggestion.new
      end

      def call(summary)
        ::JSON.generate(build_report(summary))
      end

      private

      # rubocop:disable Metrics/PerceivedComplexity
      def build_report(summary)
        {
          version: Evilution::VERSION,
          timestamp: Time.now.iso8601,
          summary: build_summary(summary),
          survived: summary.survived_results.map { |r| build_mutation_detail(r) },
          killed: summary.killed_results.map { |r| build_mutation_detail(r) },
          neutral: summary.neutral_results.map { |r| build_mutation_detail(r) },
          timed_out: summary.results.select(&:timeout?).map { |r| build_mutation_detail(r) },
          errors: summary.results.select(&:error?).map { |r| build_mutation_detail(r) },
          equivalent: summary.equivalent_results.map { |r| build_mutation_detail(r) }
        }
      end
      # rubocop:enable Metrics/PerceivedComplexity

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
          duration: summary.duration.round(4)
        }
        data[:truncated] = true if summary.truncated?
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
        detail[:child_rss_kb] = result.child_rss_kb if result.child_rss_kb
        detail[:memory_delta_kb] = result.memory_delta_kb if result.memory_delta_kb
        detail
      end
    end
  end
end
