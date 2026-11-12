# frozen_string_literal: true

require "evilution/result/run_timings"
require "evilution/parallel/work_queue"

RSpec.describe Evilution::Result::RunTimings do
  it "is empty by default" do
    timings = described_class.new

    expect([timings.phases, timings.baseline_spec_files, timings.workers]).to eq([{}, {}, []])
  end

  it "exposes what it was given" do
    worker = Evilution::Parallel::WorkQueue::WorkerStat.new(1, 2, 1.0, 2.0)
    timings = described_class.new(phases: { baseline: 1.5 }, baseline_spec_files: { "spec/a_spec.rb" => 1.4 },
                                  workers: [worker])

    expect(timings.phases).to eq(baseline: 1.5)
    expect(timings.baseline_spec_files).to eq("spec/a_spec.rb" => 1.4)
    expect(timings.workers).to eq([worker])
  end

  it "is frozen" do
    expect(described_class.new).to be_frozen
  end
end
