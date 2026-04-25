# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/line_formatters/result_line"

RSpec.describe Evilution::Reporter::CLI::LineFormatters::ResultLine do
  describe "DEFAULT_MIN_SCORE" do
    it "is 0.8" do
      expect(described_class::DEFAULT_MIN_SCORE).to eq(0.8)
    end
  end

  describe "#format" do
    let(:passing) do
      summary = double("s", score: 0.85)
      allow(summary).to receive(:success?).with(min_score: 0.8).and_return(true)
      summary
    end

    let(:failing) do
      summary = double("s", score: 0.5)
      allow(summary).to receive(:success?).with(min_score: 0.8).and_return(false)
      summary
    end

    it "outputs PASS with >= when summary passes default threshold" do
      expect(described_class.new.format(passing)).to eq("Result: PASS (score 85.00% >= 80.00%)")
    end

    it "outputs FAIL with < when summary fails default threshold" do
      expect(described_class.new.format(failing)).to eq("Result: FAIL (score 50.00% < 80.00%)")
    end

    it "uses injected min_score" do
      summary = double("s", score: 0.6)
      allow(summary).to receive(:success?).with(min_score: 0.5).and_return(true)
      expect(described_class.new(min_score: 0.5).format(summary)).to eq("Result: PASS (score 60.00% >= 50.00%)")
    end

    it "uses injected Pct" do
      pct = double("pct")
      allow(pct).to receive(:format).with(0.85).and_return("Spct")
      allow(pct).to receive(:format).with(0.8).and_return("Tpct")
      expect(described_class.new(pct: pct).format(passing)).to eq("Result: PASS (score Spct >= Tpct)")
    end
  end
end
