# frozen_string_literal: true

require_relative "../memory"

module Evilution
  module Memory
    class LeakCheck
      WARMUP_ITERATIONS = 5
      DEFAULT_ITERATIONS = 50
      DEFAULT_MAX_GROWTH_KB = 10_240 # 10 MB

      attr_reader :samples

      def initialize(iterations: DEFAULT_ITERATIONS, max_growth_kb: DEFAULT_MAX_GROWTH_KB)
        @iterations = iterations
        @max_growth_kb = max_growth_kb
        @samples = []
      end

      def run(&)
        warmup(&)
        measure(&)
        result
      end

      def growth_kb
        return 0 if samples.size < 2

        samples.last - samples.first
      end

      def passed?
        growth_kb <= @max_growth_kb
      end

      private

      def warmup(&block)
        WARMUP_ITERATIONS.times { block.call }
        GC.start
        GC.compact if GC.respond_to?(:compact)
      end

      def measure(&)
        @samples << current_rss

        @iterations.times do |i|
          yield

          next unless ((i + 1) % sample_interval).zero?

          GC.start
          @samples << current_rss
        end
      end

      def sample_interval
        @sample_interval ||= [@iterations / 10, 1].max
      end

      def current_rss
        Evilution::Memory.rss_kb || 0
      end

      def result
        {
          passed: passed?,
          growth_kb: growth_kb,
          growth_mb: growth_kb / 1024.0,
          samples: samples,
          iterations: @iterations,
          max_growth_kb: @max_growth_kb
        }
      end
    end
  end
end
