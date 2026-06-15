# frozen_string_literal: true

require_relative "calculator"

RSpec.describe CovFixtureCalculator do
  it "adds" do
    expect(described_class.new.add(2, 3)).to eq(5)
  end

  it "subtracts" do
    expect(described_class.new.sub(5, 2)).to eq(3)
  end
end
