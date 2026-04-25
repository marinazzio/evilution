# frozen_string_literal: true

require "spec_helper"
require "evilution/mcp/info_tool/status_glossary"

RSpec.describe Evilution::MCP::InfoTool::StatusGlossary do
  describe ".entries" do
    it "returns the full list of documented statuses" do
      statuses = described_class.entries.map { |e| e["status"] }
      expect(statuses).to match_array(
        %w[killed survived timeout error neutral equivalent unresolved unparseable]
      )
    end

    it "every entry has status, meaning, counted_in_score keys" do
      described_class.entries.each do |entry|
        expect(entry.keys).to contain_exactly("status", "meaning", "counted_in_score")
      end
    end

    it "counted_in_score is boolean" do
      described_class.entries.each do |entry|
        expect(entry["counted_in_score"]).to(satisfy { |v| [true, false].include?(v) })
      end
    end

    it "raises Evilution::Error when documented statuses drift from MutationResult::STATUSES" do
      stub_const("Evilution::Result::MutationResult::STATUSES", %i[killed survived timeout])
      expect { described_class.entries }.to raise_error(Evilution::Error, /status glossary drift/)
    end
  end

  describe "ENTRIES constant" do
    it "is frozen" do
      expect(described_class::ENTRIES).to be_frozen
    end

    it "freezes every entry hash" do
      described_class::ENTRIES.each do |entry|
        expect(entry).to be_frozen
      end
    end

    it "freezes every string value inside each entry" do
      described_class::ENTRIES.each do |entry|
        entry.each_value do |value|
          expect(value).to be_frozen if value.is_a?(String)
        end
      end
    end
  end
end
