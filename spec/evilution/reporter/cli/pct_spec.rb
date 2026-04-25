# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/pct"

RSpec.describe Evilution::Reporter::CLI::Pct do
  describe "#format" do
    it "formats a 0..1 value as percent with 2 decimals" do
      expect(described_class.new.format(0.5)).to eq("50.00%")
      expect(described_class.new.format(0.123)).to eq("12.30%")
      expect(described_class.new.format(0.0)).to eq("0.00%")
      expect(described_class.new.format(1.0)).to eq("100.00%")
    end

    it "rounds to 2 decimals" do
      # Matches legacy `format("%.2f%%", value * 100)` behavior in cli.rb
      # (Kernel#format uses round-half-to-even on the IEEE-754 representation).
      expect(described_class.new.format(0.12355)).to eq("12.36%")
      expect(described_class.new.format(0.12344)).to eq("12.34%")
    end

    it "supports >100% values" do
      expect(described_class.new.format(1.5)).to eq("150.00%")
    end
  end
end
