# frozen_string_literal: true

require_relative "spec_helper"
require "grade"

RSpec.describe Grade do
  before { sleep SLOW_EXAMPLE_SECONDS }

  describe ".letter" do
    { 100 => "A", 90 => "A", 89 => "B", 80 => "B", 79 => "C", 70 => "C",
      69 => "D", 60 => "D", 59 => "F", 0 => "F" }.each do |score, letter|
      it("maps #{score} to #{letter}") { expect(described_class.letter(score)).to eq(letter) }
    end
  end

  describe ".passed?" do
    it { expect(described_class.passed?(60)).to be(true) }
    it { expect(described_class.passed?(100)).to be(true) }
    it { expect(described_class.passed?(59)).to be(false) }
    it { expect(described_class.passed?(101)).to be(false) }
  end

  describe ".average" do
    it { expect(described_class.average([])).to be_nil }
    it { expect(described_class.average([80, 91])).to eq(85.5) }
    it { expect(described_class.average([70])).to eq(70.0) }
  end
end
