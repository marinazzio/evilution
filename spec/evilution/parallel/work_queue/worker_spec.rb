# frozen_string_literal: true

require "spec_helper"
require "timeout"
require "evilution/parallel/work_queue/worker"
require "evilution/parallel/work_queue/worker/loop"

RSpec.describe Evilution::Parallel::WorkQueue::Worker do
  describe ".spawn + lifecycle" do
    it "forks a child, processes one item, retires cleanly" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x * 2 }
      worker.send_item(0, 21)

      message = nil
      Timeout.timeout(5) do
        message = worker.read_result until message
      end
      expect(message).to eq([0, :ok, 42])

      worker.items_completed += 1
      worker.pending -= 1

      stat = worker.retire
      expect(stat).to be_a(Evilution::Parallel::WorkQueue::WorkerStat)
      expect(stat.pid).to eq(worker.pid)
      expect(stat.items_completed).to eq(1)
      expect(stat.busy_time).to be >= 0.0
      expect(stat.wall_time).to be >= 0.0
    end

    it "sets TEST_ENV_NUMBER per parallel_tests convention (slot 0 -> empty, slot 1 -> 2)" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |_| ENV.fetch("TEST_ENV_NUMBER", nil) }
      worker.send_item(0, nil)
      msg = nil
      Timeout.timeout(5) { msg = worker.read_result until msg }
      expect(msg[2]).to eq("")
      worker.items_completed += 1
      worker.pending -= 1
      worker.retire

      worker2 = described_class.spawn(worker_index: 1, hooks: nil) { |_| ENV.fetch("TEST_ENV_NUMBER", nil) }
      worker2.send_item(0, nil)
      msg2 = nil
      Timeout.timeout(5) { msg2 = worker2.read_result until msg2 }
      expect(msg2[2]).to eq("2")
      worker2.items_completed += 1
      worker2.pending -= 1
      worker2.retire
    end
  end

  describe "#shutdown swallows Errno::EPIPE" do
    it "does not raise when child has already exited" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x }
      worker.kill
      begin
        Process.wait(worker.pid)
      rescue Errno::ECHILD
        nil
      end
      expect { worker.shutdown }.not_to raise_error
    end
  end

  describe "#kill swallows Errno::ESRCH" do
    it "does not raise when child has already exited" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x }
      worker.shutdown
      worker.close_pipes
      worker.reap
      expect { worker.kill }.not_to raise_error
    end
  end

  describe "#to_stat" do
    it "exposes counters and timings" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x }
      worker.shutdown
      worker.close_pipes
      worker.reap
      worker.items_completed = 7
      worker.busy_time = 1.5
      worker.wall_time = 2.0
      stat = worker.to_stat
      expect(stat.pid).to eq(worker.pid)
      expect(stat.items_completed).to eq(7)
      expect(stat.busy_time).to eq(1.5)
      expect(stat.wall_time).to eq(2.0)
    end
  end
end
