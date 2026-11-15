# frozen_string_literal: true

require "evilution/mutation"
require "evilution/result/mutation_result"
require "evilution/runner/mutation_executor/isolated_run"

RSpec.describe Evilution::Runner::MutationExecutor::IsolatedRun do
  let(:mutation) { instance_double(Evilution::Mutation) }

  def result(status)
    Evilution::Result::MutationResult.new(mutation: mutation, status: status, duration: 0.1)
  end

  # Answers the queued statuses one run at a time, and notes whether each run
  # was asked for in the defined order.
  def isolator(*statuses)
    queue = statuses.dup
    runs = []
    double(:isolator).tap do |isolator|
      allow(isolator).to receive(:call) do |mutation:, test_command:, timeout:|
        runs << { defined: test_command.call(mutation), timeout: timeout }
        result(queue.shift)
      end
      isolator.define_singleton_method(:runs) { runs }
    end
  end

  # Reorders its runs unless they are inside #in_defined_order; each run says
  # whether it went in the defined order.
  def reordering_integration(reorders: true)
    Class.new do
      def initialize(reorders)
        @reorders = reorders
        @defined = false
      end

      def reorders?
        @reorders && !@defined
      end

      def in_defined_order
        @defined = true
        yield
      ensure
        @defined = false
      end

      def call(_mutation)
        !reorders?
      end
    end.new(reorders)
  end

  it "runs the mutation once under its limit, through the integration" do
    runner = isolator(:killed)

    out = described_class.new(runner).call(mutation, reordering_integration, 4.0)

    expect(out.status).to eq(:killed)
    expect(runner.runs).to eq([{ defined: false, timeout: 4.0 }])
  end

  # The reordering may have started with the very test the mutant hangs, ahead
  # of the one that would have failed on it at once.
  it "runs a reordered run that timed out again in the defined order, and reports that run" do
    runner = isolator(:timeout, :killed)

    out = described_class.new(runner).call(mutation, reordering_integration, 4.0)

    expect(out.status).to eq(:killed)
    expect(runner.runs).to eq([{ defined: false, timeout: 4.0 }, { defined: true, timeout: 4.0 }])
  end

  it "records the limit of a run that timed out in the defined order as well" do
    out = described_class.new(isolator(:timeout, :timeout)).call(mutation, reordering_integration, 4.0)

    expect(out.status).to eq(:timeout)
    expect(out.time_limit).to eq(4.0)
  end

  it "does not run again a timeout of a run that kept the defined order" do
    runner = isolator(:timeout)

    out = described_class.new(runner).call(mutation, reordering_integration(reorders: false), 4.0)

    expect(out.status).to eq(:timeout)
    expect(out.time_limit).to eq(4.0)
    expect(runner.runs.length).to eq(1)
  end

  it "does not run again a reordered run that did not time out" do
    runner = isolator(:survived)

    expect(described_class.new(runner).call(mutation, reordering_integration, 4.0).status).to eq(:survived)
    expect(runner.runs.length).to eq(1)
  end

  it "runs an integration that knows nothing of ordering once" do
    runner = isolator(:timeout)

    out = described_class.new(runner).call(mutation, ->(_m) { "cmd" }, 4.0)

    expect(out.status).to eq(:timeout)
    expect(runner.runs.length).to eq(1)
  end

  it "hands the isolator the mutation, and the integration the one the isolator runs, on both runs" do
    seen = []
    runner = double(:isolator)
    statuses = %i[timeout killed]
    allow(runner).to receive(:call) do |mutation:, test_command:, **|
      seen << mutation
      test_command.call(mutation)
      result(statuses.shift)
    end
    integration = reordering_integration
    called = []
    integration.define_singleton_method(:call) { |m| called << m }

    described_class.new(runner).call(mutation, integration, 4.0)

    expect(seen).to eq([mutation, mutation])
    expect(called).to eq([mutation, mutation])
  end

  it "records no limit on a run that finished in time" do
    expect(described_class.new(isolator(:killed)).call(mutation, reordering_integration, 4.0).time_limit).to be_nil
  end
end
