# frozen_string_literal: true

module Evilution
  module Result
    class Summary
      attr_reader :results, :duration

      def initialize(results:, duration: 0.0)
        @results = results
        @duration = duration
        freeze
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
        return 0.0 if total.zero?

        killed.to_f / (total - errors)
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
