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

    it "runs items in separate worker processes" do
      pool = described_class.new(size: 3)
      results = pool.map([1, 2, 3]) { |n| [n, Process.pid] }

      pids = results.map(&:last)
      expect(pids.uniq.size).to eq(3)
      expect(pids).not_to include(Process.pid)
    end

    it "limits concurrency to pool size" do
      pool = described_class.new(size: 2)
      results = pool.map([1, 2, 3, 4]) { |_n| Process.pid }

      pids = results.uniq
      expect(pids.size).to eq(2)
      expect(pids).not_to include(Process.pid)
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

    it "fires worker_process_start hook once per worker" do
      tmpfile = Tempfile.new("pool_worker_pids")
      hooks = Evilution::Hooks::Registry.new
      hooks.register(:worker_process_start) do
        File.open(tmpfile.path, "a") { |f| f.puts(Process.pid) }
      end
      pool = described_class.new(size: 2, hooks: hooks)

      results = pool.map([1, 2, 3, 4]) { |_n| Process.pid }

      worker_pids = results.uniq
      hook_pids = File.read(tmpfile.path).split.map(&:to_i).uniq

      expect(hook_pids.size).to eq(2)
      expect(hook_pids.sort).to eq(worker_pids.sort)
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
