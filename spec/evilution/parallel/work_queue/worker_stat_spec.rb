# frozen_string_literal: true

require "spec_helper"
require "evilution/parallel/work_queue/worker_stat"

RSpec.describe Evilution::Parallel::WorkQueue::WorkerStat do
  describe "#idle_time" do
    it "returns wall_time - busy_time" do
      stat = described_class.new(123, 5, 2.0, 10.0)
      expect(stat.idle_time).to eq(8.0)
    end
  end

  describe "#utilization" do
    it "returns busy_time / wall_time" do
      stat = described_class.new(123, 5, 4.0, 10.0)
      expect(stat.utilization).to eq(0.4)
    end

    it "returns 0.0 when wall_time is nil" do
      stat = described_class.new(123, 5, 4.0, nil)
      expect(stat.utilization).to eq(0.0)
    end

    it "returns 0.0 when wall_time is zero" do
      stat = described_class.new(123, 5, 4.0, 0.0)
      expect(stat.utilization).to eq(0.0)
    end
  end
end
