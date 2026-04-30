# frozen_string_literal: true

require "evilution/mutation"

RSpec.describe Evilution::Mutation::Slice do
  it "exposes original and mutated slice text" do
    slice = described_class.new(original: "  @age >= 18\n", mutated: "  @age > 18\n")

    expect(slice.original).to eq("  @age >= 18\n")
    expect(slice.mutated).to eq("  @age > 18\n")
  end
end
