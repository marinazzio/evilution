# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/line_formatters/error_rate_warning"

RSpec.describe Evilution::Reporter::CLI::LineFormatters::ErrorRateWarning do
  describe "#format" do
    it "returns nil when total is zero (no division by zero)" do
      summary = double("s", total: 0, errors: 0)
      expect(described_class.new.format(summary)).to be_nil
    end

    it "returns nil when errors are zero" do
      summary = double("s", total: 10, errors: 0)
      expect(described_class.new.format(summary)).to be_nil
    end

    it "returns nil when error rate is at or below threshold" do
      summary = double("s", total: 100, errors: 25)
      expect(described_class.new.format(summary)).to be_nil
    end

    it "warns when error rate exceeds threshold" do
      summary = double("s", total: 19, errors: 16)
      formatted = described_class.new.format(summary)

      expect(formatted).to match(%r{^! High error rate: 16/19 \(84\.2%\) mutations errored})
      expect(formatted).to include("score may be unreliable")
      expect(formatted).to include('"Errored mutations:" section')
    end

    it "respects a custom threshold" do
      summary = double("s", total: 100, errors: 10)
      formatted = described_class.new(threshold: 0.05).format(summary)

      expect(formatted).to match(%r{10/100 \(10\.0%\)})
    end
  end
end
