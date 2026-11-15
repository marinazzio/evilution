# frozen_string_literal: true

require_relative "calculator"
require_relative "shared/adds_group"

RSpec.describe CovFixtureCalculator do
  it_behaves_like "cov fixture adds"

  it "subtracts" do
    expect(described_class.new.sub(5, 2)).to eq(3)
  end
end
