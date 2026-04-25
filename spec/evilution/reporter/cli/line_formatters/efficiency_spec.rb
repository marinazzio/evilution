# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/line_formatters/efficiency"

RSpec.describe Evilution::Reporter::CLI::LineFormatters::Efficiency do
  describe "#format" do
    it "returns nil when duration is not positive" do
      expect(described_class.new.format(double("s", duration: 0))).to be_nil
      expect(described_class.new.format(double("s", duration: 0.0))).to be_nil
    end

    it "uses default Pct when duration is positive" do
      summary = double("s", duration: 2.5, efficiency: 0.34, mutations_per_second: 4.0)
      expect(described_class.new.format(summary)).to eq("Efficiency: 34.00% killtime, 4.00 mutations/s")
    end

    it "uses injected Pct" do
      pct = double("pct")
      allow(pct).to receive(:format).with(0.34).and_return("X%")
      summary = double("s", duration: 2.5, efficiency: 0.34, mutations_per_second: 4.0)
      expect(described_class.new(pct: pct).format(summary)).to eq("Efficiency: X% killtime, 4.00 mutations/s")
    end
  end
end
