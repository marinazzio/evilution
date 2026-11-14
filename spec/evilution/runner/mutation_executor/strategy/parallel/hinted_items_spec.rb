# frozen_string_literal: true

require "evilution/runner/mutation_executor"
require "evilution/runner/mutation_executor/strategy/parallel"

RSpec.describe Evilution::Runner::MutationExecutor::Strategy::Parallel::HintedItems do
  let(:history) { instance_double(Evilution::Runner::MutationExecutor::KillHistory) }

  it "has as many items as mutations" do
    expect(described_class.new(%i[a b], history).length).to eq(2)
  end

  it "is empty without mutations" do
    expect(described_class.new([], history)).to be_empty
  end

  it "is not empty with one" do
    expect(described_class.new([:a], history)).not_to be_empty
  end

  it "pairs a mutation with the killers its history knows at the moment it is taken" do
    known = []
    allow(history).to receive(:killers_for) { |mutation| mutation == :b ? known.dup : [] }
    items = described_class.new(%i[a b], history)

    first = items[0]
    known << "a[1:1]"

    expect([first, items[1]]).to eq([[:a, []], [:b, ["a[1:1]"]]])
  end
end
