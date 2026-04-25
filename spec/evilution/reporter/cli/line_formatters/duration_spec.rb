# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/line_formatters/duration"

RSpec.describe Evilution::Reporter::CLI::LineFormatters::Duration do
  describe "#format" do
    it "formats integer duration with 2 decimals" do
      expect(described_class.new.format(double("s", duration: 5))).to eq("Duration: 5.00s")
    end

    it "formats float duration with 2 decimals" do
      expect(described_class.new.format(double("s", duration: 2.5))).to eq("Duration: 2.50s")
    end

    it "rounds to 2 decimals" do
      expect(described_class.new.format(double("s", duration: 1.234))).to eq("Duration: 1.23s")
    end
  end
end
