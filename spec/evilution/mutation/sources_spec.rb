# frozen_string_literal: true

require "evilution/mutation"

RSpec.describe Evilution::Mutation::Sources do
  it "exposes original and mutated text" do
    sources = described_class.new(original: "a = 1", mutated: "a = 2")

    expect(sources.original).to eq("a = 1")
    expect(sources.mutated).to eq("a = 2")
  end

  it "is a value object (equal by attributes)" do
    a = described_class.new(original: "x", mutated: "y")
    b = described_class.new(original: "x", mutated: "y")

    expect(a).to eq(b)
  end
end
