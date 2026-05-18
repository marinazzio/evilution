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
    it "kills stuck workers and sets first_error" do
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) { sleep 5 }
      dispatcher = described_class.new(
        workers: [worker], items: [1], prefetch: 1,
        item_timeout: 0.2, worker_max_items: nil,
        recycle_factory: ->(_) { raise "no recycle" }
      )
      dispatcher.run
      expect(dispatcher.first_error).to be_a(Evilution::Error)
      expect(dispatcher.first_error.message).to match(/worker timed out/)

      worker.close_pipes
      begin
        Process.wait(worker.pid)
      rescue Errno::ECHILD
        nil
      end
    end

    it "actually terminates the stuck worker process" do
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) { sleep 30 }
      dispatcher = described_class.new(
        workers: [worker], items: [1], prefetch: 1,
        item_timeout: 0.2, worker_max_items: nil,
        recycle_factory: ->(_) { raise "no recycle" }
      )
      dispatcher.run

      reaped = nil
      begin
        Timeout.timeout(5) { reaped = Process.wait(worker.pid) }
      rescue Errno::ECHILD
        reaped = worker.pid
      end
      expect(reaped).to eq(worker.pid)

      alive = begin
        Process.kill(0, worker.pid)
        true
      rescue Errno::ESRCH
        false
      end
      expect(alive).to be(false)

      worker.close_pipes
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
    it "records an unexpected-exit error and finishes" do
      worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) { exit!(0) }
      dispatcher = described_class.new(
        workers: [worker], items: [1], prefetch: 1,
        item_timeout: 5, worker_max_items: nil,
        recycle_factory: ->(_) { raise "no recycle" }
      )

      run_result = nil
      expect { Timeout.timeout(5) { run_result = dispatcher.run } }.not_to raise_error

      expect(dispatcher.first_error).to be_a(Evilution::Error)
      expect(dispatcher.first_error.message).to match(/exited unexpectedly/)
      expect(run_result.results).to eq([nil])
      expect(run_result.retired).to be_empty

      worker.close_pipes
      begin
        Process.wait(worker.pid)
      rescue Errno::ECHILD
        nil
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
