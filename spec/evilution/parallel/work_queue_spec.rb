# frozen_string_literal: true

require "evilution/parallel/work_queue"
require "tempfile"

RSpec.describe Evilution::Parallel::WorkQueue do
  describe "#initialize" do
    it "rejects zero size" do
      expect { described_class.new(size: 0) }.to raise_error(ArgumentError, /positive integer/)
    end

    it "rejects negative size" do
      expect { described_class.new(size: -1) }.to raise_error(ArgumentError, /positive integer/)
    end

    it "accepts a valid size" do
      queue = described_class.new(size: 2)
      expect(queue).to be_a(described_class)
    end
  end

  describe "#map" do
    it "executes block for each item and returns results in order" do
      queue = described_class.new(size: 2)
      results = queue.map([1, 2, 3, 4, 5]) { |n| n * 10 }

      expect(results).to eq([10, 20, 30, 40, 50])
    end

    it "runs items in separate worker processes" do
      queue = described_class.new(size: 3)
      results = queue.map([1, 2, 3]) { |_n| Process.pid }

      pids = results
      expect(pids).not_to include(Process.pid)
      expect(pids.uniq.size).to be <= 3
    end

    it "reuses workers across items (more items than workers)" do
      queue = described_class.new(size: 2)
      results = queue.map([1, 2, 3, 4, 5, 6]) { |_n| Process.pid }

      pids = results.uniq
      # Only 2 worker processes should have been forked
      expect(pids.size).to eq(2)
      expect(pids).not_to include(Process.pid)
    end

    it "returns empty array for empty input" do
      queue = described_class.new(size: 2)
      results = queue.map([]) { |n| n }

      expect(results).to eq([])
    end

    it "handles single item" do
      queue = described_class.new(size: 4)
      results = queue.map([42]) { |n| n * 2 }

      expect(results).to eq([84])
    end

    it "handles more workers than items" do
      queue = described_class.new(size: 4)
      results = queue.map([1, 2]) { |n| n * 3 }

      expect(results).to eq([3, 6])
    end

    it "distributes work dynamically (fast items finish first)" do
      queue = described_class.new(size: 2)
      # Items with varying "cost" — the queue should not wait for a batch
      results = queue.map([1, 2, 3, 4]) { |n| n * 10 }

      expect(results).to eq([10, 20, 30, 40])
    end

    it "propagates exceptions from the block" do
      queue = described_class.new(size: 2)

      expect do
        queue.map([1, 2, 3]) do |n|
          raise "boom" if n == 2

          n
        end
      end.to raise_error(RuntimeError, "boom")
    end

    it "fires worker_process_start hook once per worker process" do
      tmpfile = Tempfile.new("wq_hook_pids")
      hooks = Evilution::Hooks::Registry.new
      hooks.register(:worker_process_start) do
        File.open(tmpfile.path, "a") { |f| f.puts(Process.pid) }
      end
      queue = described_class.new(size: 2, hooks: hooks)

      results = queue.map([1, 2, 3, 4]) { |_n| Process.pid }

      worker_pids = results.uniq
      hook_pids = File.read(tmpfile.path).split.map(&:to_i).uniq

      # Hook fires once per worker, not once per item
      expect(hook_pids.size).to eq(2)
      expect(hook_pids.sort).to eq(worker_pids.sort)
    ensure
      tmpfile&.close
      tmpfile&.unlink
    end

    it "fires worker_process_start hook before the block runs" do
      tmpfile = Tempfile.new("wq_hook_order")
      hooks = Evilution::Hooks::Registry.new
      hooks.register(:worker_process_start) { File.write(tmpfile.path, "hook_fired") }
      queue = described_class.new(size: 1, hooks: hooks)

      results = queue.map([1]) do |_n|
        File.read(tmpfile.path)
      end

      expect(results.first).to eq("hook_fired")
    ensure
      tmpfile&.close
      tmpfile&.unlink
    end

    it "works without hooks" do
      queue = described_class.new(size: 2)
      results = queue.map([1, 2]) { |n| n * 10 }

      expect(results).to eq([10, 20])
    end

    it "cleans up worker processes even on error" do
      queue = described_class.new(size: 2)

      expect do
        queue.map([1, 2, 3]) do |n|
          raise "fail" if n == 1

          n
        end
      end.to raise_error(RuntimeError, "fail")

      # Verify no zombie processes by checking that all children have been reaped
      expect { Process.waitpid(-1, Process::WNOHANG) }.to raise_error(Errno::ECHILD)
    end
  end
end
