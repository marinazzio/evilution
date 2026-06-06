# frozen_string_literal: true

require "spec_helper"
require "timeout"
require "evilution/parallel/work_queue/dispatcher"
require "evilution/parallel/work_queue/worker"
require "evilution/parallel/work_queue/worker/loop"

RSpec.describe Evilution::Parallel::WorkQueue::Dispatcher do
  describe "#run with single worker, single item" do
    it "returns results in order" do
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) { |x| x + 1 }
      dispatcher = described_class.new(
        workers: [worker], items: [10], prefetch: 1,
        item_timeout: 5, worker_max_items: nil,
        recycle_factory: ->(_) { raise "should not recycle" }
      )
      run_result = dispatcher.run
      expect(run_result.results).to eq([11])
      expect(run_result.retired).to be_empty
      expect(dispatcher.first_error).to be_nil

      worker.shutdown
      worker.close_pipes
      worker.reap
    end
  end

  describe "#run with worker_max_items triggering recycle" do
    it "spawns a replacement after K items" do
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) { |x| x }
      replacement = nil
      factory = lambda do |old|
        replacement = Evilution::Parallel::WorkQueue::Worker.spawn(
          worker_index: old.worker_index, hooks: nil
        ) { |x| x }
      end

      dispatcher = described_class.new(
        workers: [worker], items: [1, 2, 3], prefetch: 1,
        item_timeout: 5, worker_max_items: 2,
        recycle_factory: factory
      )
      run_result = dispatcher.run

      expect(run_result.results).to eq([1, 2, 3])
      expect(run_result.retired.length).to eq(1)
      expect(run_result.retired.first.items_completed).to eq(2)

      replacement.shutdown if replacement
      replacement.close_pipes if replacement
      replacement.reap if replacement
    end
  end

  describe "#run when worker block raises" do
    it "captures first error" do
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) { raise "boom" }
      dispatcher = described_class.new(
        workers: [worker], items: [1], prefetch: 1,
        item_timeout: 5, worker_max_items: nil,
        recycle_factory: ->(_) { raise "no recycle" }
      )
      dispatcher.run
      expect(dispatcher.first_error).to be_a(StandardError)
      expect(dispatcher.first_error.message).to eq("boom")

      worker.shutdown
      worker.close_pipes
      worker.reap
    end
  end

  describe "#run on item_timeout" do
    it "marks the stuck item TIMED_OUT and does not set first_error" do
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) { sleep 30 }
      dispatcher = described_class.new(
        workers: [worker], items: [1], prefetch: 1,
        item_timeout: 0.2, worker_max_items: nil,
        recycle_factory: ->(_) { raise "no recycle" }
      )
      run_result = dispatcher.run

      expect(run_result.results).to eq([Evilution::Parallel::WorkQueue::TIMED_OUT])
      expect(dispatcher.first_error).to be_nil
      expect(run_result.retired.length).to eq(1)

      worker.close_pipes
    end

    it "actually terminates the stuck worker process" do
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) { sleep 30 }
      dispatcher = described_class.new(
        workers: [worker], items: [1], prefetch: 1,
        item_timeout: 0.2, worker_max_items: nil,
        recycle_factory: ->(_) { raise "no recycle" }
      )
      Timeout.timeout(5) { dispatcher.run }

      alive = begin
        Process.kill(0, worker.pid)
        true
      rescue Errno::ESRCH
        false
      end
      expect(alive).to be(false)

      worker.close_pipes
    end

    it "recycles the stuck worker and finishes the remaining items" do
      recycle_calls = 0
      replacement = nil
      factory = lambda do |old|
        recycle_calls += 1
        replacement = Evilution::Parallel::WorkQueue::Worker.spawn(
          worker_index: old.worker_index, hooks: nil
        ) { |x| x }
      end
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) do |x|
        sleep 30 if x.zero?
        x
      end
      dispatcher = described_class.new(
        workers: [worker], items: [0, 1], prefetch: 1,
        item_timeout: 0.3, worker_max_items: nil,
        recycle_factory: factory
      )
      run_result = Timeout.timeout(10) { dispatcher.run }

      expect(run_result.results).to eq([Evilution::Parallel::WorkQueue::TIMED_OUT, 1])
      expect(recycle_calls).to eq(1)
      expect(dispatcher.first_error).to be_nil

      worker.close_pipes
      if replacement
        replacement.shutdown
        replacement.close_pipes
        replacement.reap
      end
    end

    it "times out only the stuck worker, leaving healthy workers' results intact" do
      workers = [0, 1].map do |i|
        Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: i, hooks: nil) do |x|
          sleep 30 if x.zero?
          x
        end
      end
      dispatcher = described_class.new(
        workers: workers, items: [0, 10, 20, 30], prefetch: 1,
        item_timeout: 0.5, worker_max_items: nil,
        recycle_factory: ->(_) { raise "no recycle expected once items exhausted" }
      )
      run_result = Timeout.timeout(10) { dispatcher.run }

      expect(run_result.results[0]).to eq(Evilution::Parallel::WorkQueue::TIMED_OUT)
      expect(run_result.results[1..]).to eq([10, 20, 30])
      expect(dispatcher.first_error).to be_nil

      workers.each(&:close_pipes)
    end
  end

  describe "#run when prefetch exceeds the item count" do
    it "does not over-dispatch and yields exactly the available results" do
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) { |x| x + 1 }
      dispatcher = described_class.new(
        workers: [worker], items: [10], prefetch: 5,
        item_timeout: 5, worker_max_items: nil,
        recycle_factory: ->(_) { raise "should not recycle" }
      )
      run_result = dispatcher.run

      expect(run_result.results).to eq([11])
      expect(run_result.retired).to be_empty
      expect(dispatcher.first_error).to be_nil

      worker.shutdown
      worker.close_pipes
      worker.reap
    end
  end

  describe "#run when a worker process dies without replying" do
    it "marks the in-flight item DIED, recycles, and finishes without first_error" do
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) { exit!(0) }
      dispatcher = described_class.new(
        workers: [worker], items: [1], prefetch: 1,
        item_timeout: 5, worker_max_items: nil,
        recycle_factory: ->(_) { raise "no recycle" }
      )

      run_result = nil
      expect { Timeout.timeout(5) { run_result = dispatcher.run } }.not_to raise_error

      expect(dispatcher.first_error).to be_nil
      expect(run_result.results).to eq([Evilution::Parallel::WorkQueue::DIED])
      expect(run_result.retired.length).to eq(1)

      worker.close_pipes
    end

    it "recycles the dead worker and finishes the remaining items" do
      recycle_calls = 0
      replacement = nil
      factory = lambda do |old|
        recycle_calls += 1
        replacement = Evilution::Parallel::WorkQueue::Worker.spawn(
          worker_index: old.worker_index, hooks: nil
        ) { |x| x }
      end
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) do |x|
        exit!(0) if x.zero?
        x
      end
      dispatcher = described_class.new(
        workers: [worker], items: [0, 1], prefetch: 1,
        item_timeout: 5, worker_max_items: nil,
        recycle_factory: factory
      )
      run_result = Timeout.timeout(10) { dispatcher.run }

      expect(run_result.results).to eq([Evilution::Parallel::WorkQueue::DIED, 1])
      expect(recycle_calls).to eq(1)
      expect(dispatcher.first_error).to be_nil

      worker.close_pipes
      if replacement
        replacement.shutdown
        replacement.close_pipes
        replacement.reap
      end
    end
  end

  describe "#run when worker block raises (result slot)" do
    it "leaves the result slot nil rather than storing the error object" do
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) { raise "boom" }
      dispatcher = described_class.new(
        workers: [worker], items: [1], prefetch: 1,
        item_timeout: 5, worker_max_items: nil,
        recycle_factory: ->(_) { raise "no recycle" }
      )
      run_result = dispatcher.run

      expect(run_result.results).to eq([nil])
      expect(dispatcher.first_error).to be_a(StandardError)

      worker.shutdown
      worker.close_pipes
      worker.reap
    end
  end

  describe "#run with prefetch keeping a recycle-eligible worker busy" do
    it "drains in-flight work before recycling and recycles exactly once" do
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) { |x| x }
      replacement = nil
      recycle_calls = 0
      factory = lambda do |old|
        recycle_calls += 1
        replacement = Evilution::Parallel::WorkQueue::Worker.spawn(
          worker_index: old.worker_index, hooks: nil
        ) { |x| x }
      end

      dispatcher = described_class.new(
        workers: [worker], items: [1, 2, 3, 4], prefetch: 2,
        item_timeout: 5, worker_max_items: 2,
        recycle_factory: factory
      )
      run_result = dispatcher.run

      expect(run_result.results).to eq([1, 2, 3, 4])
      expect(recycle_calls).to eq(1)
      expect(run_result.retired.length).to eq(1)
      expect(dispatcher.first_error).to be_nil

      replacement.shutdown if replacement
      replacement.close_pipes if replacement
      replacement.reap if replacement
    end
  end

  describe "#run does not recycle when no work remains" do
    it "skips the recycle factory once items are exhausted" do
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) { |x| x }
      recycle_calls = 0
      factory = ->(_) { recycle_calls += 1 }

      dispatcher = described_class.new(
        workers: [worker], items: [1, 2], prefetch: 1,
        item_timeout: 5, worker_max_items: 2,
        recycle_factory: factory
      )
      run_result = dispatcher.run

      expect(run_result.results).to eq([1, 2])
      expect(recycle_calls).to eq(0)
      expect(run_result.retired).to be_empty
      expect(dispatcher.first_error).to be_nil

      worker.shutdown
      worker.close_pipes
      worker.reap
    end
  end

  describe "#run keeps a clean error state across a recycle" do
    it "does not surface a spurious unexpected-exit error after recycling" do
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) { |x| x }
      replacement = nil
      factory = lambda do |old|
        replacement = Evilution::Parallel::WorkQueue::Worker.spawn(
          worker_index: old.worker_index, hooks: nil
        ) { |x| x }
      end

      dispatcher = described_class.new(
        workers: [worker], items: [1, 2, 3], prefetch: 1,
        item_timeout: 5, worker_max_items: 2,
        recycle_factory: factory
      )
      run_result = dispatcher.run

      expect(run_result.results).to eq([1, 2, 3])
      expect(dispatcher.first_error).to be_nil
      expect(run_result.retired.length).to eq(1)

      replacement.shutdown if replacement
      replacement.close_pipes if replacement
      replacement.reap if replacement
    end
  end
end
