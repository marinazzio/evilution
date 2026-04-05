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
      temp = Tempfile.new("work_queue_dynamic_order")

      begin
        results = queue.map([1, 2, 3, 4]) do |n|
          # Make item 2 significantly slower than the others
          if n == 2
            sleep 0.3
          else
            sleep 0.05
          end

          File.open(temp.path, "a") { |f| f.puts(n) }
          n * 10
        end

        expect(results).to eq([10, 20, 30, 40])

        completion_order = File.read(temp.path).lines.map(&:to_i)
        expect(completion_order.sort).to eq([1, 2, 3, 4])

        # The slow item (2) should finish after faster items 3 and 4
        expect(completion_order.index(3)).to be < completion_order.index(2)
        expect(completion_order.index(4)).to be < completion_order.index(2)
      ensure
        temp.close!
      end
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

    it "raises a clear error when a worker exits unexpectedly" do
      queue = described_class.new(size: 2)

      expect do
        queue.map([1, 2, 3]) do |n|
          exit!(1) if n == 2

          n
        end
      end.to raise_error(Evilution::Error, /worker process exited unexpectedly/)
    end

    it "works without hooks" do
      queue = described_class.new(size: 2)
      results = queue.map([1, 2]) { |n| n * 10 }

      expect(results).to eq([10, 20])
    end

    context "with prefetch" do
      it "defaults prefetch to 1" do
        queue = described_class.new(size: 2)
        results = queue.map([1, 2, 3, 4]) { |n| n * 10 }

        expect(results).to eq([10, 20, 30, 40])
      end

      it "pre-buffers items in worker pipes when prefetch > 1" do
        temp = Tempfile.new("wq_prefetch_prebuffer")

        begin
          queue = described_class.new(size: 2, prefetch: 2)
          results = queue.map([1, 2, 3, 4, 5, 6]) do |n|
            # Make even-numbered items slower so completion order reflects scheduling
            sleep(n.even? ? 0.2 : 0.05)
            File.open(temp.path, "a") { |f| f.puts(n) }
            n * 10
          end

          expect(results).to eq([10, 20, 30, 40, 50, 60])

          completion_order = File.read(temp.path).lines.map(&:to_i)
          # With effective prefetch and concurrent workers, completion order should
          # differ from simple input order, indicating out-of-order processing
          expect(completion_order).not_to eq(completion_order.sort)
        ensure
          temp.close!
        end
      end

      it "rejects prefetch less than 1" do
        expect { described_class.new(size: 2, prefetch: 0) }.to raise_error(ArgumentError, /prefetch must be a positive integer/)
      end

      it "handles prefetch larger than item count" do
        queue = described_class.new(size: 2, prefetch: 10)
        results = queue.map([1, 2]) { |n| n * 5 }

        expect(results).to eq([5, 10])
      end

      it "reduces idle time with prefetch on variable-cost work" do
        temp = Tempfile.new("wq_prefetch_order")

        begin
          # With prefetch=2 and round-robin seeding, worker A gets items 1,3 and worker B gets 2,4
          # When worker A finishes item 1 quickly, item 3 is already in its pipe
          queue = described_class.new(size: 2, prefetch: 2)
          results = queue.map([1, 2, 3, 4, 5, 6]) do |n|
            sleep(n == 2 ? 0.3 : 0.05)
            File.open(temp.path, "a") { |f| f.puts(n) }
            n * 10
          end

          expect(results).to eq([10, 20, 30, 40, 50, 60])

          completion_order = File.read(temp.path).lines.map(&:to_i)
          expect(completion_order.sort).to eq([1, 2, 3, 4, 5, 6])
        ensure
          temp.close!
        end
      end
    end

    context "with worker stats" do
      it "tracks per-worker completion counts" do
        queue = described_class.new(size: 2)
        queue.map([1, 2, 3, 4, 5, 6]) { |n| n * 10 }

        stats = queue.worker_stats
        expect(stats.length).to eq(2)
        expect(stats.sum(&:items_completed)).to eq(6)
        stats.each do |stat|
          expect(stat.items_completed).to be >= 1
        end
      end

      it "tracks worker PIDs in stats" do
        queue = described_class.new(size: 2)
        queue.map([1, 2]) { |_n| Process.pid }

        stats = queue.worker_stats
        pids = stats.map(&:pid)
        expect(pids.uniq.size).to eq(2)
        expect(pids).not_to include(Process.pid)
      end

      it "returns empty stats before map is called" do
        queue = described_class.new(size: 2)
        expect(queue.worker_stats).to eq([])
      end

      it "returns empty stats for empty input" do
        queue = described_class.new(size: 2)
        queue.map([]) { |n| n }
        expect(queue.worker_stats).to eq([])
      end

      it "tracks busy_time per worker" do
        queue = described_class.new(size: 2)
        queue.map([1, 2, 3, 4]) do |_n|
          sleep 0.05
          :done
        end

        stats = queue.worker_stats
        stats.each do |stat|
          expect(stat.busy_time).to be_a(Float)
          expect(stat.busy_time).to be > 0.0
        end
      end

      it "tracks wall_time per worker" do
        queue = described_class.new(size: 2)
        queue.map([1, 2, 3, 4]) { |n| n }

        stats = queue.worker_stats
        stats.each do |stat|
          expect(stat.wall_time).to be_a(Float)
          expect(stat.wall_time).to be > 0.0
        end
      end

      it "computes idle_time as wall_time minus busy_time" do
        queue = described_class.new(size: 2)
        queue.map([1, 2, 3, 4]) { |n| n }

        stats = queue.worker_stats
        stats.each do |stat|
          expect(stat.idle_time).to be_a(Float)
          expect(stat.idle_time).to be >= 0.0
          expect(stat.idle_time).to be_within(0.001).of(stat.wall_time - stat.busy_time)
        end
      end

      it "computes utilization as busy_time / wall_time" do
        queue = described_class.new(size: 2)
        queue.map([1, 2]) do |_n|
          sleep 0.05
          :done
        end

        stats = queue.worker_stats
        stats.each do |stat|
          expect(stat.utilization).to be_a(Float)
          expect(stat.utilization).to be > 0.0
          expect(stat.utilization).to be <= 1.0
        end
      end

      it "reports positive utilization for all workers" do
        queue = described_class.new(size: 2)
        queue.map([1, 2, 3, 4]) do |_n|
          sleep 0.05
          :done
        end

        stats = queue.worker_stats
        stats.each do |stat|
          expect(stat.utilization).to be > 0.0
          expect(stat.utilization).to be <= 1.0
          expect(stat.busy_time).to be <= stat.wall_time
        end
      end
    end

    it "raises an error when a worker hangs beyond the item timeout" do
      queue = described_class.new(size: 1, item_timeout: 1)

      expect do
        queue.map([1]) do |_n|
          sleep 60
          :done
        end
      end.to raise_error(Evilution::Error, /timed out/)
    end

    it "removes dead worker pipes from the select set" do
      queue = described_class.new(size: 2)

      expect do
        queue.map([1, 2, 3, 4]) do |n|
          exit!(1) if n == 1
          n * 10
        end
      end.to raise_error(Evilution::Error, /worker process exited unexpectedly/)
    end

    it "cleans up worker processes even on error" do
      tmpfile = Tempfile.new("wq_cleanup_pids")
      hooks = Evilution::Hooks::Registry.new
      hooks.register(:worker_process_start) do
        File.open(tmpfile.path, "a") { |f| f.puts(Process.pid) }
      end
      queue = described_class.new(size: 2, hooks: hooks)

      expect do
        queue.map([1, 2, 3]) do |n|
          raise "fail" if n == 1

          n
        end
      end.to raise_error(RuntimeError, "fail")

      worker_pids = File.read(tmpfile.path).split.map(&:to_i)
      worker_pids.each do |pid|
        expect { Process.waitpid(pid, Process::WNOHANG) }.to raise_error(Errno::ECHILD)
      end
    ensure
      tmpfile&.close
      tmpfile&.unlink
    end
  end
end
