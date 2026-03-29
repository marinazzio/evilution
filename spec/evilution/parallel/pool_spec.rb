# frozen_string_literal: true

require "evilution/parallel/pool"

RSpec.describe Evilution::Parallel::Pool do
  describe "#initialize" do
    it "rejects zero size" do
      expect { described_class.new(size: 0) }.to raise_error(ArgumentError, /positive integer/)
    end

    it "rejects negative size" do
      expect { described_class.new(size: -1) }.to raise_error(ArgumentError, /positive integer/)
    end
  end

  describe "#map" do
    it "executes block for each item and returns results in order" do
      pool = described_class.new(size: 2)
      results = pool.map([1, 2, 3]) { |n| n * 10 }

      expect(results).to eq([10, 20, 30])
    end

    it "runs batch items concurrently in separate processes" do
      pool = described_class.new(size: 3)
      results = pool.map([1, 2, 3]) { |n| [n, Process.pid] }

      pids = results.map(&:last)
      # All items should run in different child processes (not the parent)
      expect(pids.uniq.size).to eq(3)
      expect(pids).not_to include(Process.pid)
    end

    it "limits concurrency to pool size via batching" do
      pool = described_class.new(size: 2)
      results = pool.map([1, 2, 3, 4]) { |n| [n, Process.pid] }

      # 4 items with size 2 = 2 batches; pids within a batch differ
      batch1_pids = results[0..1].map(&:last)
      batch2_pids = results[2..3].map(&:last)
      expect(batch1_pids.uniq.size).to eq(2)
      expect(batch2_pids.uniq.size).to eq(2)
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

    it "fires worker_process_start hook after fork in each worker" do
      tmpfile = Tempfile.new("pool_worker_pids")
      hooks = Evilution::Hooks::Registry.new
      hooks.register(:worker_process_start) do
        File.open(tmpfile.path, "a") { |f| f.puts(Process.pid) }
      end
      pool = described_class.new(size: 2, hooks: hooks)

      results = pool.map([1, 2]) { |n| [n, Process.pid] }

      worker_pids = results.map(&:last)
      hook_pids = File.read(tmpfile.path).split.map(&:to_i).uniq

      expect(worker_pids.uniq.size).to eq(2)
      expect(worker_pids).not_to include(Process.pid)
      expect(hook_pids.sort).to eq(worker_pids.uniq.sort)
    ensure
      tmpfile&.close
      tmpfile&.unlink
    end

    it "fires worker_process_start hook before the block runs" do
      tmpfile = Tempfile.new("pool_hook_order")
      hooks = Evilution::Hooks::Registry.new
      hooks.register(:worker_process_start) { File.write(tmpfile.path, "hook_fired") }
      pool = described_class.new(size: 1, hooks: hooks)

      results = pool.map([1]) do |_n|
        File.read(tmpfile.path)
      end

      expect(results.first).to eq("hook_fired")
    ensure
      tmpfile&.close
      tmpfile&.unlink
    end

    it "works without hooks (backwards compatible)" do
      pool = described_class.new(size: 2)
      results = pool.map([1, 2]) { |n| n * 10 }

      expect(results).to eq([10, 20])
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
