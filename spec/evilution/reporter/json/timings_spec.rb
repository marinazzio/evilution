# frozen_string_literal: true

require "evilution/reporter/json"
require "evilution/result/summary"
require "evilution/parallel/work_queue"

RSpec.describe Evilution::Reporter::JSON::Timings do
  let(:mutation) { double("Mutation") }

  def result(**phases)
    timings = phases.empty? ? nil : Evilution::Result::MutationTimings.new(**phases)
    Evilution::Result::MutationResult.new(mutation: mutation, status: :killed, timings: timings)
  end

  def summary(results: [], **timings)
    Evilution::Result::Summary.new(results: results, timings: Evilution::Result::RunTimings.new(**timings))
  end

  it "lists the phases of the run, rounded" do
    out = described_class.new.call(summary(phases: { baseline: 1.234567, execution: 10.0 }))

    expect(out[:phases]).to eq(baseline: 1.2346, execution: 10.0)
  end

  it "lists each baseline spec file with its duration, in the order they ran" do
    out = described_class.new.call(summary(baseline_spec_files: { "spec/b_spec.rb" => 0.123456, "spec/a_spec.rb" => 2 }))

    expect(out[:baseline]).to eq([{ spec_file: "spec/b_spec.rb", duration: 0.1235 },
                                  { spec_file: "spec/a_spec.rb", duration: 2 }])
  end

  it "sums each mutation phase over the mutations" do
    out = described_class.new.call(summary(results: [result(apply: 0.1, test_run: 1.0), result(apply: 0.2), result]))

    expect(out[:mutations]).to eq(apply: 0.3, test_run: 1.0, confirmation: 0.0, queue_wait: 0.0)
  end

  it "lists each worker with its utilisation" do
    worker = Evilution::Parallel::WorkQueue::WorkerStat.new(42, 3, 1.5, 2.0)

    out = described_class.new.call(summary(workers: [worker]))

    expect(out[:workers]).to eq([{ pid: 42, items: 3, busy: 1.5, wall: 2.0, utilization: 0.75 }])
  end

  it "reports a worker whose figures never arrived as zero busy and wall time" do
    worker = Evilution::Parallel::WorkQueue::WorkerStat.new(42, 3, 0.0, 0.0)

    out = described_class.new.call(summary(workers: [worker]))

    expect(out[:workers]).to eq([{ pid: 42, items: 3, busy: 0.0, wall: 0.0, utilization: 0.0 }])
  end

  it "has an empty section for each part a run did not measure" do
    expect(described_class.new.call(summary)).to eq(
      phases: {}, baseline: [], mutations: { apply: 0.0, test_run: 0.0, confirmation: 0.0, queue_wait: 0.0 }, workers: []
    )
  end

  describe "#mutation_fields" do
    it "gives a mutation's timings, rounded" do
      expect(described_class.new.mutation_fields(result(apply: 0.123456))).to eq(timings: { apply: 0.1235 })
    end

    it "gives nothing for a mutation that measured nothing" do
      expect(described_class.new.mutation_fields(result)).to eq({})
    end

    it "gives the limit a timed-out mutation ran under, rounded, beside its timings" do
      timed_out = result(test_run: 10.2).with_time_limit(10.12344)

      expect(described_class.new.mutation_fields(timed_out)).to eq(time_limit: 10.1234, timings: { test_run: 10.2 })
    end
  end
end
