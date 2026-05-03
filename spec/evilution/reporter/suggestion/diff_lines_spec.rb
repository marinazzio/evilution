# frozen_string_literal: true

require "evilution/reporter/suggestion/diff_lines"

RSpec.describe Evilution::Reporter::Suggestion::DiffLines do
  describe ".from_diff" do
    it "returns the original and mutated lines stripped of markers" do
      result = described_class.from_diff("- a >= b\n+ a > b")
      expect(result.original).to eq("a >= b")
      expect(result.mutated).to eq("a > b")
    end

    it "returns nil for original when the diff lacks a `- ` line" do
      result = described_class.from_diff("+ a > b")
      expect(result.original).to be_nil
      expect(result.mutated).to eq("a > b")
    end

    it "returns nil for mutated when the diff lacks a `+ ` line" do
      result = described_class.from_diff("- a >= b")
      expect(result.original).to eq("a >= b")
      expect(result.mutated).to be_nil
    end

    it "returns a frozen instance" do
      result = described_class.from_diff("- a >= b\n+ a > b")
      expect(result).to be_frozen
    end
  end
end
