# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/line_formatters/unresolved_rate_warning"

RSpec.describe Evilution::Reporter::CLI::LineFormatters::UnresolvedRateWarning do
  describe "#format" do
    it "returns nil when total is zero (no division by zero)" do
      summary = double("s", total: 0, unresolved: 0, score_denominator: 0)
      expect(described_class.new.format(summary)).to be_nil
    end

    it "returns nil when total is zero even though unresolved is present (no division by zero)" do
      summary = double("s", total: 0, unresolved: 5, score_denominator: 0)
      expect(described_class.new.format(summary)).to be_nil
    end

    it "returns nil when there are no unresolved mutations" do
      summary = double("s", total: 10, unresolved: 0, score_denominator: 10)
      expect(described_class.new.format(summary)).to be_nil
    end

    it "returns nil when unresolved rate is strictly below the default threshold" do
      summary = double("s", total: 100, unresolved: 10, score_denominator: 90)
      expect(described_class.new.format(summary)).to be_nil
    end

    it "returns nil when unresolved rate is at or below threshold" do
      summary = double("s", total: 100, unresolved: 25, score_denominator: 75)
      expect(described_class.new.format(summary)).to be_nil
    end

    it "warns when unresolved rate exceeds threshold" do
      summary = double("s", total: 19, unresolved: 16, score_denominator: 3)
      formatted = described_class.new.format(summary)

      expect(formatted).to match(%r{^! High unresolved rate: 16/19 \(84\.2%\)})
      expect(formatted).to include("--spec")
    end

    # The all-unresolved case is the headline bug (EV-z7f5): score_denominator
    # collapses to 0 so Score prints a bare "0.00% (0/0)" that reads like a
    # genuine failure. The warning must make clear nothing was measured.
    it "warns distinctly when nothing was measurable (denominator zero)" do
      summary = double("s", total: 1250, unresolved: 1250, score_denominator: 0)
      formatted = described_class.new.format(summary)

      expect(formatted).to include("No matching tests resolved")
      expect(formatted).to include("no mutations were measured")
      expect(formatted).to include("all 1250/1250")
      expect(formatted).to include("--spec")
      expect(formatted).not_to include("0/0")
    end

    # A zero denominator can also arise from a mix of unresolved + errors (etc.),
    # not only an all-unresolved run. The wording must not claim every mutation
    # was a missing test in that case.
    it "does not attribute a mixed denominator-zero run solely to missing tests" do
      summary = double("s", total: 10, unresolved: 6, score_denominator: 0)
      formatted = described_class.new.format(summary)

      expect(formatted).to include("No mutations were measured")
      expect(formatted).to include("6/10")
      expect(formatted).to include("--spec")
      expect(formatted).not_to include("No matching tests resolved")
      expect(formatted).not_to match(/\ball\b/)
    end

    it "respects a custom threshold" do
      summary = double("s", total: 100, unresolved: 10, score_denominator: 90)
      formatted = described_class.new(threshold: 0.05).format(summary)

      expect(formatted).to match(%r{10/100 \(10\.0%\)})
    end
  end
end
