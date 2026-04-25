# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/section"
require "evilution/reporter/cli/section_renderer"

RSpec.describe Evilution::Reporter::CLI::SectionRenderer do
  describe "#call" do
    let(:formatter) { instance_double("ItemFormatter") }
    let(:summary) { double("summary", items: %i[a b]) }

    it "returns [] when fetcher returns empty array" do
      section = Evilution::Reporter::CLI::Section.new(
        title: "Things:",
        fetcher: ->(_) { [] },
        formatter: formatter
      )
      expect(described_class.new.call(section, summary)).to eq([])
    end

    it "returns ['', title, formatter.format(item) for each item] for non-empty fetch" do
      allow(formatter).to receive(:format).with(:a).and_return("  a-line")
      allow(formatter).to receive(:format).with(:b).and_return("  b-line")
      section = Evilution::Reporter::CLI::Section.new(
        title: "Things:",
        fetcher: lambda(&:items),
        formatter: formatter
      )
      expect(described_class.new.call(section, summary)).to eq([
                                                                 "",
                                                                 "Things:",
                                                                 "  a-line",
                                                                 "  b-line"
                                                               ])
    end

    it "calls a callable title with the items array" do
      allow(formatter).to receive(:format).and_return("  x")
      section = Evilution::Reporter::CLI::Section.new(
        title: ->(items) { "Found #{items.length}:" },
        fetcher: ->(_) { [1, 2, 3] },
        formatter: formatter
      )
      result = described_class.new.call(section, summary)
      expect(result[1]).to eq("Found 3:")
    end
  end
end
