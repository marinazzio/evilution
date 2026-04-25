# frozen_string_literal: true

require "evilution/result/mutation_result"
require "evilution/runner/mutation_executor/neutralization_pipeline"

RSpec.describe Evilution::Runner::MutationExecutor::NeutralizationPipeline do
  let(:mutation) { instance_double("Mutation") }
  let(:result) { Evilution::Result::MutationResult.new(mutation: mutation, status: :survived, duration: 0.01) }

  it "returns the original result when neutralizer list is empty" do
    pipeline = described_class.new([])
    expect(pipeline.call(result)).to be(result)
  end

  it "applies a single neutralizer and returns its output" do
    nz = double(:nz)
    out = Evilution::Result::MutationResult.new(mutation: mutation, status: :neutral, duration: 0.01)
    allow(nz).to receive(:call).with(result, foo: 1).and_return(out)

    pipeline = described_class.new([nz])
    expect(pipeline.call(result, foo: 1)).to be(out)
  end

  it "chains neutralizers, threading each output as input to the next" do
    nz1 = double(:nz1)
    nz2 = double(:nz2)
    mid = Evilution::Result::MutationResult.new(mutation: mutation, status: :neutral, duration: 0.01)
    out = Evilution::Result::MutationResult.new(mutation: mutation, status: :neutral, duration: 0.02)
    allow(nz1).to receive(:call).with(result).and_return(mid)
    allow(nz2).to receive(:call).with(mid).and_return(out)

    pipeline = described_class.new([nz1, nz2])
    expect(pipeline.call(result)).to be(out)
  end

  it "passes ctx kwargs to every neutralizer" do
    nz1 = double(:nz1)
    nz2 = double(:nz2)
    expect(nz1).to receive(:call).with(result, baseline_result: :bl).and_return(result)
    expect(nz2).to receive(:call).with(result, baseline_result: :bl).and_return(result)

    described_class.new([nz1, nz2]).call(result, baseline_result: :bl)
  end
end
