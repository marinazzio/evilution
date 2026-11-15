# frozen_string_literal: true

require "evilution/mutation"
require "evilution/runner/mutation_executor/runless_verdict"
require "evilution/runner/mutation_executor/probe_first"

RSpec.describe Evilution::Runner::MutationExecutor::RunlessVerdict do
  def mutation(unparseable: false)
    instance_double(Evilution::Mutation, unparseable?: unparseable)
  end

  it "gives an unparseable mutation its verdict without a run" do
    mut = mutation(unparseable: true)
    result = described_class.new.call(mut)

    expect([result.status, result.mutation, result.duration]).to eq([:unparseable, mut, 0.0])
  end

  it "gives a mutation no test executes its verdict without a run" do
    mut = mutation
    coverage = double("Integration")
    allow(coverage).to receive(:uncovered?).with(mut).and_return(true)

    result = described_class.new(coverage: coverage).call(mut)

    expect([result.status, result.mutation]).to eq([:uncovered, mut])
  end

  it "leaves a mutation a test executes to its run" do
    coverage = double("Integration", uncovered?: false)

    expect(described_class.new(coverage: coverage).call(mutation)).to be_nil
  end

  it "leaves every parseable mutation to its run without coverage to ask" do
    expect(described_class.new.call(mutation)).to be_nil
  end

  it "reports a mutation its subject's sentinel implies as a survivor, naming the sentinel" do
    mut = mutation
    probe = instance_double(Evilution::Runner::MutationExecutor::ProbeFirst)
    allow(probe).to receive(:implied_by).with(mut).and_return("method_body_to_raise")

    result = described_class.new(probe: probe).call(mut)

    expect([result.status, result.implied_by, result.duration, result.mutation])
      .to eq([:survived, "method_body_to_raise", 0.0, mut])
  end

  it "leaves a mutation no sentinel implies to its run" do
    probe = instance_double(Evilution::Runner::MutationExecutor::ProbeFirst, implied_by: nil)

    expect(described_class.new(probe: probe).call(mutation)).to be_nil
  end

  it "reports a mutation no test executes as uncovered even when a sentinel implies it" do
    probe = instance_double(Evilution::Runner::MutationExecutor::ProbeFirst, implied_by: "method_body_to_raise")
    coverage = double("Integration", uncovered?: true)

    expect(described_class.new(coverage: coverage, probe: probe).call(mutation).status).to eq(:uncovered)
  end

  it "does not ask about coverage for an unparseable mutation" do
    coverage = double("Integration")
    expect(coverage).not_to receive(:uncovered?)

    described_class.new(coverage: coverage).call(mutation(unparseable: true))
  end
end
