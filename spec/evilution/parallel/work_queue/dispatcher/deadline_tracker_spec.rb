# frozen_string_literal: true

require "spec_helper"
require "evilution/parallel/work_queue/dispatcher"

RSpec.describe Evilution::Parallel::WorkQueue::Dispatcher::DeadlineTracker do
  # Minimal stand-in for a Worker: only deadline + pending matter to the tracker.
  Worker = Struct.new(:deadline, :pending) unless defined?(Worker)

  let(:clock_now) { [1000.0] }
  let(:clock) { -> { clock_now.first } }
  let(:workers) { [] }

  subject(:tracker) { described_class.new(item_timeout: 5.0, workers: workers, clock: clock) }

  def advance(seconds)
    clock_now[0] += seconds
  end

  describe "when item_timeout is disabled (nil)" do
    subject(:tracker) { described_class.new(item_timeout: nil, workers: workers, clock: clock) }

    it "has no overdue workers and starts no clock" do
      w = Worker.new(nil, 1)
      workers << w
      tracker.start(w)
      expect(w.deadline).to be_nil
      expect(tracker.overdue).to eq([])
    end

    it "select_timeout is nil (block on IO.select indefinitely)" do
      expect(tracker.select_timeout).to be_nil
    end
  end

  describe "#start" do
    it "sets a worker's deadline to now + item_timeout" do
      w = Worker.new(nil, 1)
      tracker.start(w)
      expect(w.deadline).to eq(1005.0)
    end

    it "does not move an already-set deadline (one clock per in-flight item)" do
      w = Worker.new(1003.0, 1)
      tracker.start(w)
      expect(w.deadline).to eq(1003.0)
    end
  end

  describe "#refresh" do
    it "re-arms the deadline while the worker still has pending work" do
      w = Worker.new(1002.0, 2)
      tracker.refresh(w)
      expect(w.deadline).to eq(1005.0)
    end

    it "clears the deadline once the worker is idle" do
      w = Worker.new(1002.0, 0)
      tracker.refresh(w)
      expect(w.deadline).to be_nil
    end
  end

  describe "#select_timeout" do
    it "returns time remaining until the nearest worker deadline" do
      workers << Worker.new(1008.0, 1) << Worker.new(1004.0, 1)
      expect(tracker.select_timeout).to eq(4.0) # 1004 - 1000
    end

    it "clamps a passed deadline to zero" do
      workers << Worker.new(995.0, 1)
      expect(tracker.select_timeout).to eq(0)
    end

    it "falls back to the raw timeout when no worker is on the clock" do
      workers << Worker.new(nil, 0)
      expect(tracker.select_timeout).to eq(5.0)
    end
  end

  describe "#overdue" do
    it "returns workers whose deadline passed while still holding in-flight work" do
      stuck = Worker.new(999.0, 1)
      idle_past = Worker.new(999.0, 0) # past deadline but nothing pending
      future = Worker.new(1009.0, 1)
      workers.push(stuck, idle_past, future)

      expect(tracker.overdue).to eq([stuck])
    end

    it "becomes non-empty only after time advances past a deadline" do
      w = Worker.new(1003.0, 1)
      workers << w
      expect(tracker.overdue).to eq([])
      advance(4) # now 1004 > 1003
      expect(tracker.overdue).to eq([w])
    end
  end
end
