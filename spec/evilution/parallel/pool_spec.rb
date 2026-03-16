# frozen_string_literal: true

require "evilution/parallel/pool"

RSpec.describe Evilution::Parallel::Pool do
  describe "#map" do
    it "executes block for each item and returns results in order" do
      pool = described_class.new(size: 2)
      results = pool.map([1, 2, 3]) { |n| n * 10 }

      expect(results).to eq([10, 20, 30])
    end

    it "runs items concurrently up to pool size" do
      pool = described_class.new(size: 3)
      started_at = []
      mutex = Mutex.new

      pool.map([1, 2, 3]) do |n|
        mutex.synchronize { started_at << Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        sleep 0.1
        n
      end

      # All 3 should start nearly simultaneously (within 50ms)
      expect(started_at.max - started_at.min).to be < 0.05
    end

    it "limits concurrency to pool size" do
      pool = described_class.new(size: 2)
      concurrent_count = 0
      max_concurrent = 0
      mutex = Mutex.new

      pool.map([1, 2, 3, 4]) do |n|
        mutex.synchronize do
          concurrent_count += 1
          max_concurrent = [max_concurrent, concurrent_count].max
        end
        sleep 0.05
        mutex.synchronize { concurrent_count -= 1 }
        n
      end

      expect(max_concurrent).to eq(2)
    end

    it "returns empty array for empty input" do
      pool = described_class.new(size: 2)
      results = pool.map([]) { |n| n }

      expect(results).to eq([])
    end

    it "handles single item" do
      pool = described_class.new(size: 4)
      results = pool.map([42]) { |n| n * 2 }

      expect(results).to eq([84])
    end

    it "propagates exceptions from the block" do
      pool = described_class.new(size: 2)

      expect do
        pool.map([1, 2, 3]) do |n|
          raise "boom" if n == 2

          n
        end
      end.to raise_error(RuntimeError, "boom")
    end
  end
end
