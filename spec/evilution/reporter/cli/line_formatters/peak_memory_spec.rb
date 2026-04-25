# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/line_formatters/peak_memory"

RSpec.describe Evilution::Reporter::CLI::LineFormatters::PeakMemory do
  describe "#format" do
    it "returns nil when peak_memory_mb is nil" do
      expect(described_class.new.format(double("s", peak_memory_mb: nil))).to be_nil
    end

    it "formats with 1 decimal when peak_memory_mb is set" do
      expect(described_class.new.format(double("s", peak_memory_mb: 120.5))).to eq("Peak memory: 120.5 MB")
    end

    it "rounds to 1 decimal" do
      expect(described_class.new.format(double("s", peak_memory_mb: 120.55))).to eq("Peak memory: 120.6 MB")
    end
  end
end
