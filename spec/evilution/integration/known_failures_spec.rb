# frozen_string_literal: true

require "evilution/integration/known_failures"

RSpec.describe Evilution::Integration::KnownFailures do
  subject(:known) { described_class.new(%w[a b]) }

  describe "#empty?" do
    it "is true when the baseline saw nothing fail" do
      expect(described_class.new([])).to be_empty
    end

    it "is false when the baseline saw something fail" do
      expect(known).not_to be_empty
    end
  end

  describe "#only?" do
    it "is true when every failed test was already failing" do
      expect(known.only?(%w[a])).to be true
      expect(known.only?(%w[b a])).to be true
    end

    it "is false when something else failed too" do
      expect(known.only?(%w[a c])).to be false
    end

    it "is false when nothing is named as failed" do
      expect(known.only?([])).to be false
    end

    it "is false when the baseline saw nothing fail" do
      expect(described_class.new([]).only?(%w[a])).to be false
    end

    it "takes the ids as a set" do
      expect(described_class.new(Set["a"]).only?(%w[a])).to be true
    end
  end
end
