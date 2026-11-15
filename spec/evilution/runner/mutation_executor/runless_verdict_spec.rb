# frozen_string_literal: true

require "evilution/mutation"
require "evilution/runner/mutation_executor/runless_verdict"

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

    expect(described_class.new(coverage: coverage).call(mut).status).to eq(:uncovered)
  end

  it "leaves a mutation a test executes to its run" do
    coverage = double("Integration", uncovered?: false)

    expect(described_class.new(coverage: coverage).call(mutation)).to be_nil
  end

  it "leaves every parseable mutation to its run without coverage to ask" do
    expect(described_class.new.call(mutation)).to be_nil
  end

  it "does not ask about coverage for an unparseable mutation" do
    coverage = double("Integration")
    expect(coverage).not_to receive(:uncovered?)

    described_class.new(coverage: coverage).call(mutation(unparseable: true))
  end
end
