# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/line_formatters/result_line"

RSpec.describe Evilution::Reporter::CLI::LineFormatters::ResultLine do
  describe "#format" do
    let(:passing) do
      summary = double("s", score: 0.85, unresolved_targets?: false)
      allow(summary).to receive(:success?).with(min_score: 0.8).and_return(true)
      summary
    end

    let(:failing) do
      summary = double("s", score: 0.5, unresolved_targets?: false)
      allow(summary).to receive(:success?).with(min_score: 0.8).and_return(false)
      summary
    end

    # EV-39t1 / GH #1603: printing a verdict against a threshold nobody set
    # implied a gate that the exit code did not enforce.
    it "reports the score without a verdict when no minimum is configured" do
      summary = double("s", score: 0.85, unresolved_targets?: false)

      expect(described_class.new.format(summary)).to eq("Result: 85.00% (no minimum score set)")
    end

    it "reports the score without a verdict when the minimum is zero" do
      summary = double("s", score: 0.0, unresolved_targets?: false)

      expect(described_class.new(min_score: 0.0).format(summary)).to eq("Result: 0.00% (no minimum score set)")
    end

    it "outputs PASS with >= when summary passes the configured threshold" do
      expect(described_class.new(min_score: 0.8).format(passing)).to eq("Result: PASS (score 85.00% >= 80.00%)")
    end

    it "outputs FAIL with < when summary fails the configured threshold" do
      expect(described_class.new(min_score: 0.8).format(failing)).to eq("Result: FAIL (score 50.00% < 80.00%)")
    end

    it "uses injected min_score" do
      summary = double("s", score: 0.6, unresolved_targets?: false)
      allow(summary).to receive(:success?).with(min_score: 0.5).and_return(true)
      expect(described_class.new(min_score: 0.5).format(summary)).to eq("Result: PASS (score 60.00% >= 50.00%)")
    end

    # The score speaks only for the files that resolved, so saying "score X < Y"
    # would point at the wrong problem.
    it "states the reason when a target file resolved to no spec" do
      summary = double("s", score: 1.0, unresolved_targets?: true, unresolved_target_files: ["lib/untested.rb"])

      expect(described_class.new.format(summary)).to eq(
        "Result: FAIL (1 target file has no resolvable spec)"
      )
    end

    it "pluralises the reason for several unresolved target files" do
      summary = double("s", score: 1.0, unresolved_targets?: true,
                            unresolved_target_files: ["a.rb", "b.rb"])

      expect(described_class.new.format(summary)).to eq(
        "Result: FAIL (2 target files have no resolvable spec)"
      )
    end

    it "uses injected Pct" do
      pct = double("pct")
      allow(pct).to receive(:format).with(0.85).and_return("Spct")
      allow(pct).to receive(:format).with(0.8).and_return("Tpct")

      expect(described_class.new(pct: pct, min_score: 0.8).format(passing)).to eq("Result: PASS (score Spct >= Tpct)")
    end
  end
end
