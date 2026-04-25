# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/line_formatters/mutations"

RSpec.describe Evilution::Reporter::CLI::LineFormatters::Mutations do
  let(:summary) do
    double(
      "summary",
      total: 10, killed: 8, survived: 1, timed_out: 1,
      neutral: 0, equivalent: 0, unresolved: 0, unparseable: 0, skipped: 0
    )
  end

  describe "#format" do
    it "returns base line when all conditional categories are zero" do
      expect(described_class.new.format(summary)).to eq(
        "Mutations: 10 total, 8 killed, 1 survived, 1 timed out"
      )
    end

    it "appends neutral when positive" do
      allow(summary).to receive(:neutral).and_return(2)
      expect(described_class.new.format(summary)).to include(", 2 neutral")
    end

    it "appends equivalent when positive" do
      allow(summary).to receive(:equivalent).and_return(3)
      expect(described_class.new.format(summary)).to include(", 3 equivalent")
    end

    it "appends unresolved when positive" do
      allow(summary).to receive(:unresolved).and_return(4)
      expect(described_class.new.format(summary)).to include(", 4 unresolved")
    end

    it "appends unparseable when positive" do
      allow(summary).to receive(:unparseable).and_return(5)
      expect(described_class.new.format(summary)).to include(", 5 unparseable")
    end

    it "appends skipped when positive" do
      allow(summary).to receive(:skipped).and_return(6)
      expect(described_class.new.format(summary)).to include(", 6 skipped")
    end
  end
end
