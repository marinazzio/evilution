# frozen_string_literal: true

module Evilution
  module Result
    class Summary
      attr_reader :results, :duration

      def initialize(results:, duration: 0.0, truncated: false)
        @results = results
        @duration = duration
        @truncated = truncated
        freeze
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

      def score
        denominator = total - errors
        return 0.0 if denominator.zero?

        killed.to_f / denominator
      end

      def success?(min_score: 1.0)
        score >= min_score
      end

      def survived_results
        results.select(&:survived?)
      end

      def killed_results
        results.select(&:killed?)
      end
    end
  end
end
