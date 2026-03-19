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

      def rss_available?
        !Evilution::Memory.rss_kb.nil?
      end

      def growth_kb
        return nil if samples.any?(&:nil?)
        return 0 if samples.size < 2

        samples.last - samples.first
      end

      def passed?
        kb = growth_kb
        return false if kb.nil?

        kb <= @max_growth_kb
      end

      private

      def warmup(&block)
        WARMUP_ITERATIONS.times { block.call }
        GC.start
        GC.compact if GC.respond_to?(:compact)
      end

      def measure(&)
        @samples << Evilution::Memory.rss_kb

        @iterations.times do |i|
          yield

          next unless ((i + 1) % sample_interval).zero?

          GC.start
          @samples << Evilution::Memory.rss_kb
        end

        take_final_sample
      end

      def take_final_sample
        return if (@iterations % sample_interval).zero?

        GC.start
        @samples << Evilution::Memory.rss_kb
      end

      def sample_interval
        @sample_interval ||= [@iterations / 10, 1].max
      end

      def result
        {
          passed: passed?,
          growth_kb: growth_kb,
          growth_mb: growth_kb ? growth_kb / 1024.0 : nil,
          samples: samples,
          iterations: @iterations,
          max_growth_kb: @max_growth_kb,
          rss_available: rss_available?
        }
      end
    end
  end
end
