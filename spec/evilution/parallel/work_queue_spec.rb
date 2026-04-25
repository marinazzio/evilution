# frozen_string_literal: true

require "evilution/parallel/work_queue"

# This spec covers the public API contract of WorkQueue and a small set of
# end-to-end smoke tests that exercise real Process.fork. Granular coverage of
# the internals lives in per-class specs:
#   - work_queue/worker_stat_spec.rb
#   - work_queue/validators/*_spec.rb
#   - work_queue/channel_spec.rb, work_queue/channel/frame_spec.rb
#   - work_queue/worker_spec.rb, work_queue/worker/loop_spec.rb
#   - work_queue/dispatcher_spec.rb
#   - work_queue/collection_state_spec.rb
RSpec.describe Evilution::Parallel::WorkQueue do
  describe "constants" do
    it "exposes SHUTDOWN, STATS, TIMING_GRACE_PERIOD, and WorkerStat at the public name" do
      expect(described_class::SHUTDOWN).to eq(:__shutdown__)
      expect(described_class::STATS).to eq(:__stats__)
      expect(described_class::TIMING_GRACE_PERIOD).to be_a(Numeric)
      expect(described_class::WorkerStat).to be_a(Class)
    end
  end

  describe "#initialize argument validation (smoke)" do
    it "rejects invalid size via PositiveInt validator" do
      expect { described_class.new(size: 0) }.to raise_error(ArgumentError, /positive integer/)
    end

    it "rejects invalid prefetch via PositiveInt validator" do
      expect { described_class.new(size: 1, prefetch: 0) }.to raise_error(ArgumentError, /prefetch must be a positive integer/)
    end

    it "rejects invalid item_timeout via OptionalPositiveNumber validator" do
      expect { described_class.new(size: 1, item_timeout: -1) }.to raise_error(ArgumentError, /item_timeout/)
    end

    it "rejects invalid worker_max_items via OptionalPositiveInt validator" do
      expect { described_class.new(size: 1, worker_max_items: 0) }.to raise_error(ArgumentError, /worker_max_items/)
    end

    it "accepts valid arguments" do
      queue = described_class.new(size: 2, prefetch: 1, item_timeout: 5, worker_max_items: 3)
      expect(queue).to be_a(described_class)
    end
  end

  describe "#map" do
    it "returns [] for empty input without spawning workers" do
      queue = described_class.new(size: 2)
      expect(queue.map([]) { |n| n }).to eq([])
      expect(queue.worker_stats).to eq([])
    end

    it "executes block for each item and returns results in input order (golden path)" do
      queue = described_class.new(size: 2)
      results = queue.map([1, 2, 3, 4, 5]) { |n| n * 10 }

      expect(results).to eq([10, 20, 30, 40, 50])
    end

    it "propagates exceptions raised by the user block" do
      queue = described_class.new(size: 2)

      expect do
        queue.map([1, 2, 3]) do |n|
          raise "boom" if n == 2

          n
        end
      end.to raise_error(RuntimeError, "boom")
    end

    it "raises a timeout error when an item exceeds item_timeout" do
      queue = described_class.new(size: 1, item_timeout: 1)

      expect do
        queue.map([1]) do |_n|
          sleep 60
          :done
        end
      end.to raise_error(Evilution::Error, /timed out/)
    end

    it "recycles workers after worker_max_items items are completed" do
      queue = described_class.new(size: 1, worker_max_items: 2)
      results = queue.map([1, 2, 3, 4, 5, 6]) { |n| n * 10 }

      expect(results).to eq([10, 20, 30, 40, 50, 60])
      stats = queue.worker_stats
      # More retired stats than worker pool size proves recycling happened.
      expect(stats.length).to be > 1
      expect(stats.map(&:pid).uniq.size).to eq(stats.length)
    end
  end

  describe "#worker_stats" do
    it "returns frozen WorkerStat dups with the correct field types after map" do
      queue = described_class.new(size: 2)
      queue.map([1, 2, 3, 4]) do |_n|
        sleep 0.01
        :done
      end

      stats = queue.worker_stats
      expect(stats).to be_an(Array)
      expect(stats.length).to eq(2)
      stats.each do |stat|
        expect(stat).to be_a(described_class::WorkerStat)
        expect(stat).to be_frozen
        expect(stat.pid).to be_a(Integer)
        expect(stat.items_completed).to be_a(Integer)
        expect(stat.busy_time).to be_a(Float)
        expect(stat.wall_time).to be_a(Float)
        expect(stat.idle_time).to be_a(Float)
        expect(stat.utilization).to be_a(Float)
      end
      expect(stats.sum(&:items_completed)).to eq(4)
    end
  end
end
