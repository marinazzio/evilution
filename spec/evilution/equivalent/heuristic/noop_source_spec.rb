# frozen_string_literal: true

RSpec.describe Evilution::Equivalent::Heuristic::NoopSource do
  subject(:heuristic) { described_class.new }

  it "matches when original and mutated source are identical" do
    mutation = double("Mutation", original_source: "x + 1", mutated_source: "x + 1")

    expect(heuristic.match?(mutation)).to be true
  end

  it "does not match when sources differ" do
    mutation = double("Mutation", original_source: "x + 1", mutated_source: "x - 1")

    expect(heuristic.match?(mutation)).to be false
  end
end
