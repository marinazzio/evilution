# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/line_formatters/score"

RSpec.describe Evilution::Reporter::CLI::LineFormatters::Score do
  describe "#format" do
    let(:summary) { double("summary", score: 0.85, killed: 17, score_denominator: 20) }

    it "uses default Pct" do
      expect(described_class.new.format(summary)).to eq("Score: 85.00% (17/20)")
    end

    it "uses injected Pct" do
      pct = double("pct")
      allow(pct).to receive(:format).with(0.85).and_return("X%")
      expect(described_class.new(pct: pct).format(summary)).to eq("Score: X% (17/20)")
    end
  end
end
