# frozen_string_literal: true

require "spec_helper"
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
      results, retired = dispatcher.run
      expect(results).to eq([11])
      expect(retired).to be_empty
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
      results, retired = dispatcher.run

      expect(results).to eq([1, 2, 3])
      expect(retired.length).to eq(1)
      expect(retired.first.items_completed).to eq(2)

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
      _results, _retired = dispatcher.run
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
      _results, _retired = dispatcher.run
      expect(dispatcher.first_error).to be_a(Evilution::Error)
      expect(dispatcher.first_error.message).to match(/worker timed out/)

      worker.close_pipes
      begin
        Process.wait(worker.pid)
      rescue Errno::ECHILD
        nil
      end
    end
  end
end
