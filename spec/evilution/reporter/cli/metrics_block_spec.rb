# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/metrics_block"

RSpec.describe Evilution::Reporter::CLI::MetricsBlock do
  describe "#call" do
    it "returns nil-filtered formatted lines from configured formatters" do
      summary = double("summary")
      f1 = double("f1")
      allow(f1).to receive(:format).with(summary).and_return("line-1")
      f2 = double("f2")
      allow(f2).to receive(:format).with(summary).and_return(nil)
      f3 = double("f3")
      allow(f3).to receive(:format).with(summary).and_return("line-3")
      block = described_class.new(lines: [f1, f2, f3])
      expect(block.call(summary)).to eq(%w[line-1 line-3])
    end
  end

  describe "DEFAULT_LINES" do
    it "is a frozen array of LineFormatter instances" do
      expect(described_class::DEFAULT_LINES).to be_frozen
      described_class::DEFAULT_LINES.each do |line|
        expect(line).to respond_to(:format)
      end
    end

    it "contains 5 default formatters in the canonical order" do
      classes = described_class::DEFAULT_LINES.map(&:class)
      expect(classes).to eq([Evilution::Reporter::CLI::LineFormatters::Mutations,
                             Evilution::Reporter::CLI::LineFormatters::Score,
                             Evilution::Reporter::CLI::LineFormatters::Duration,
                             Evilution::Reporter::CLI::LineFormatters::Efficiency,
                             Evilution::Reporter::CLI::LineFormatters::PeakMemory])
    end
  end
end
