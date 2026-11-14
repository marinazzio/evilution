# frozen_string_literal: true

require "evilution/mutation"
require "evilution/subject"
require "evilution/result/mutation_result"
require "evilution/runner/mutation_executor"
require "evilution/runner/mutation_executor/probe_first"
require "evilution/runner/mutation_executor/probe_first_run"
require "evilution/runner/mutation_executor/result_notifier"

RSpec.describe Evilution::Runner::MutationExecutor::ProbeFirstRun do
  let(:probe) { Evilution::Runner::MutationExecutor::ProbeFirst.new }
  let(:notifier) { instance_double(Evilution::Runner::MutationExecutor::ResultNotifier, start: nil, finish: nil) }
  let(:state) { instance_double(Evilution::Subject, name: "Gate#state", line_number: 3) }

  before { allow(notifier).to receive(:notify).and_return(:continue) }

  def mutation(operator: "integer_literal", line: 4)
    instance_double(Evilution::Mutation, operator_name: operator, line: line, subject: state,
                                         file_path: "lib/gate.rb")
  end

  def execution(results, truncated: false, infra_retried: 0, worker_stats: [])
    Evilution::Runner::MutationExecutor::ExecutionResult.new(results: results, truncated: truncated,
                                                             infra_retried: infra_retried,
                                                             worker_stats: worker_stats)
  end

  # Runs each batch the way a strategy does: every mutation gets `status`
  # unless the probe already implies it, and the batch's notifier hears of
  # each result in turn.
  def batch_runner(statuses, batches: [])
    lambda do |batch, batch_notifier|
      batches << batch
      batch_notifier.start(batch.length)
      results = batch.each_with_index.map do |mutation, index|
        result = Evilution::Result::MutationResult.new(
          mutation: mutation, status: probe.implied_by(mutation) ? :survived : statuses.fetch(mutation)
        )
        batch_notifier.notify(result, index + 1)
        result
      end
      batch_notifier.finish
      execution(results)
    end
  end

  let(:sentinel) { mutation(operator: "method_body_to_raise", line: 3) }
  let(:sibling) { mutation(line: 4) }
  let(:other) { mutation(line: 5) }

  it "runs the sentinels in a batch before the other mutations" do
    batches = []
    runner = batch_runner({ sentinel => :killed, sibling => :killed, other => :killed }, batches: batches)

    described_class.new(probe: probe, notifier: notifier).call([sibling, sentinel, other], &runner)

    expect(batches).to eq([[sentinel], [sibling, other]])
  end

  it "hands the second batch a probe that knows the sentinels' verdicts" do
    implied = []
    runner = lambda do |batch, _batch_notifier|
      implied.concat(batch.map { |m| probe.implied_by(m) })
      statuses = batch.map { |m| Evilution::Result::MutationResult.new(mutation: m, status: :survived) }
      execution(statuses)
    end

    described_class.new(probe: probe, notifier: notifier).call([sibling, sentinel], &runner)

    expect(implied).to eq([nil, "method_body_to_raise"])
  end

  it "returns the results in the order the mutations came in" do
    runner = batch_runner({ sentinel => :killed, sibling => :survived, other => :killed })

    execution = described_class.new(probe: probe, notifier: notifier).call([sibling, sentinel, other], &runner)

    expect(execution.results.map(&:mutation)).to eq([sibling, sentinel, other])
  end

  it "starts and finishes the notifier once, for all the mutations" do
    runner = batch_runner({ sentinel => :killed, sibling => :killed, other => :killed })

    described_class.new(probe: probe, notifier: notifier).call([sibling, sentinel, other], &runner)

    expect(notifier).to have_received(:start).once.with(3)
    expect(notifier).to have_received(:finish).once
  end

  it "numbers the results across both batches" do
    runner = batch_runner({ sentinel => :killed, sibling => :killed, other => :killed })
    heard = []
    allow(notifier).to receive(:notify) { |result, index| heard << [result.mutation, index] }

    described_class.new(probe: probe, notifier: notifier).call([sibling, sentinel, other], &runner)

    expect(heard).to eq([[sentinel, 1], [sibling, 2], [other, 3]])
  end

  it "passes on the notifier's answer, so fail-fast can stop either batch" do
    allow(notifier).to receive(:notify).and_return(:truncate)
    answers = []
    runner = lambda do |batch, batch_notifier|
      answers << batch_notifier.notify(Evilution::Result::MutationResult.new(mutation: batch.first, status: :killed), 1)
      execution([])
    end

    described_class.new(probe: probe, notifier: notifier).call([sentinel, sibling], &runner)

    expect(answers).to eq(%i[truncate truncate])
  end

  it "skips the second batch when the first was truncated" do
    batches = []
    runner = lambda do |batch, _batch_notifier|
      batches << batch
      execution([Evilution::Result::MutationResult.new(mutation: batch.first, status: :survived)], truncated: true)
    end

    execution = described_class.new(probe: probe, notifier: notifier).call([sibling, sentinel], &runner)

    expect([batches, execution.truncated, execution.results.map(&:mutation)]).to eq([[[sentinel]], true, [sentinel]])
  end

  it "reports the run truncated when the second batch was" do
    runner = ->(batch, _n) { execution([], truncated: batch.include?(sibling)) }

    expect(described_class.new(probe: probe, notifier: notifier).call([sibling, sentinel], &runner).truncated).to be true
  end

  it "adds up the re-runs and keeps the workers of both batches" do
    runner = ->(batch, _n) { execution([], infra_retried: batch.length, worker_stats: [batch.length]) }

    execution = described_class.new(probe: probe, notifier: notifier).call([sibling, sentinel, other], &runner)

    expect([execution.infra_retried, execution.worker_stats, execution.truncated]).to eq([3, [1, 2], false])
  end
end
