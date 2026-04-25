# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/trailer"

RSpec.describe Evilution::Reporter::CLI::Trailer do
  describe "#call" do
    it "returns nil-filtered lines from configured formatters" do
      summary = double("summary")
      f1 = double("f1")
      allow(f1).to receive(:format).with(summary).and_return(nil)
      f2 = double("f2")
      allow(f2).to receive(:format).with(summary).and_return("trailer-line")
      trailer = described_class.new(lines: [f1, f2])
      expect(trailer.call(summary)).to eq(["trailer-line"])
    end
  end

  describe "DEFAULT_LINES" do
    it "is a frozen array containing TruncationNotice and ResultLine instances" do
      expect(described_class::DEFAULT_LINES).to be_frozen
      classes = described_class::DEFAULT_LINES.map(&:class)
      expect(classes).to eq([Evilution::Reporter::CLI::LineFormatters::TruncationNotice,
                             Evilution::Reporter::CLI::LineFormatters::ResultLine])
    end
  end
end
