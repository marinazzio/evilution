# frozen_string_literal: true

require "evilution/compare/diff_extractor/evilution"

RSpec.describe Evilution::Compare::DiffExtractor::Evilution do
  subject(:extractor) { described_class.new }

  describe "#call" do
    it "splits into minus and plus payloads, dropping markers" do
      diff = "- a + b\n+ a - b"
      expect(extractor.call(diff)).to eq(minus: ["a + b"], plus: ["a - b"])
    end

    it "handles multi-line +/- blocks" do
      diff = "- a\n- b\n+ x\n+ y"
      expect(extractor.call(diff)).to eq(minus: %w[a b], plus: %w[x y])
    end

    it "returns empty arrays for an empty diff" do
      expect(extractor.call("")).to eq(minus: [], plus: [])
    end

    it "ignores lines that lack the '- ' / '+ ' marker" do
      diff = "- a\nrandom\n+ b"
      expect(extractor.call(diff)).to eq(minus: ["a"], plus: ["b"])
    end

    it "tolerates a nil diff" do
      expect(extractor.call(nil)).to eq(minus: [], plus: [])
    end
  end
end
