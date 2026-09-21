# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/line_formatters/score"

RSpec.describe Evilution::Reporter::CLI::LineFormatters::Score do
  describe "#format" do
    let(:summary) { double("summary", score: 0.85, killed: 17, score_denominator: 20, total: 20, neutral: 0) }

    it "uses default Pct" do
      expect(described_class.new.format(summary)).to eq("Score: 85.00% (17/20)")
    end

    # EV-5pob / GH #1606: full marks over a fraction of the run reads as a
    # verdict on all of it unless the line says what it covered.
    it "says how much of the run was verified when mutations were left out" do
      partial = double("summary", score: 1.0, killed: 10, score_denominator: 10, total: 17, neutral: 7)

      expect(described_class.new.format(partial))
        .to eq("Score: 100.00% (10/10 verified of 17 mutations, 7 neutral)")
    end

    it "leaves the line alone when nothing was left out" do
      whole = double("summary", score: 1.0, killed: 17, score_denominator: 17, total: 17, neutral: 0)

      expect(described_class.new.format(whole)).to eq("Score: 100.00% (17/17)")
    end

    # Unresolved and the rest also shrink the denominator; the neutral count is
    # only named when there is one.
    it "reports the remainder without a neutral count when none were neutral" do
      partial = double("summary", score: 1.0, killed: 5, score_denominator: 5, total: 12, neutral: 0)

      expect(described_class.new.format(partial))
        .to eq("Score: 100.00% (5/5 verified of 12 mutations)")
    end

    it "uses injected Pct" do
      pct = double("pct")
      allow(pct).to receive(:format).with(0.85).and_return("X%")

      expect(described_class.new(pct: pct).format(summary)).to eq("Score: X% (17/20)")
    end
  end
end
