# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli"
require "evilution/result/summary"
require_relative "../../support/fixtures/cli_golden_summary"

# Public API + smoke tests for the CLI reporter composition root.
# Granular behavior is covered by:
#   - spec/evilution/reporter/cli/golden_output_spec.rb (byte-equal regression)
#   - spec/evilution/reporter/cli/{pct,section,section_renderer,metrics_block,trailer}_spec.rb
#   - spec/evilution/reporter/cli/line_formatters/*
#   - spec/evilution/reporter/cli/item_formatters/*
RSpec.describe Evilution::Reporter::CLI do
  let(:empty_summary) { Evilution::Result::Summary.new(results: [], duration: 0.0) }

  describe "constants" do
    it "exposes SEPARATOR as 44 equals signs" do
      expect(described_class::SEPARATOR).to eq("=" * 44)
    end

    it "exposes DEFAULT_SECTIONS as a frozen array of 7 Section instances" do
      expect(described_class::DEFAULT_SECTIONS).to be_frozen
      expect(described_class::DEFAULT_SECTIONS.length).to eq(7)
      described_class::DEFAULT_SECTIONS.each do |section|
        expect(section).to be_a(described_class::Section)
      end
    end
  end

  describe "#initialize" do
    it "succeeds with no args (default composition)" do
      expect { described_class.new }.not_to raise_error
    end

    it "accepts header, metrics_block, section_renderer, sections, trailer kwargs" do
      expect do
        described_class.new(
          header: instance_double(Evilution::Reporter::CLI::LineFormatters::Header, format: "H"),
          metrics_block: instance_double(Evilution::Reporter::CLI::MetricsBlock, call: ["M"]),
          section_renderer: instance_double(Evilution::Reporter::CLI::SectionRenderer),
          sections: [],
          trailer: instance_double(Evilution::Reporter::CLI::Trailer, call: ["T"])
        )
      end.not_to raise_error
    end
  end

  describe "#call" do
    it "returns a String" do
      expect(described_class.new.call(empty_summary)).to be_a(String)
    end

    it "renders header, separator, metrics, and trailer for an empty summary" do
      output = described_class.new.call(empty_summary)
      lines = output.split("\n")

      expect(lines[0]).to start_with("Evilution v")
      expect(lines[1]).to eq("=" * 44)
      expect(lines[2]).to eq("")
      expect(output).to include("Mutations: ")
      expect(output).to include("Score: ")
      expect(output).to include("Duration: ")
      expect(output).to include("Result: ")
    end

    it "omits all section headers when summary has no items in any section" do
      output = described_class.new.call(empty_summary)

      expect(output).not_to include("Survived mutations")
      expect(output).not_to include("Neutral mutations")
      expect(output).not_to include("Equivalent mutations")
      expect(output).not_to include("Unresolved mutations")
      expect(output).not_to include("Unparseable mutations")
      expect(output).not_to include("Errored mutations")
      expect(output).not_to include("Disabled mutations")
    end

    it "uses injected sections when provided (empty list produces no section output)" do
      summary = CliGoldenSummary.call
      output = described_class.new(sections: []).call(summary)

      expect(output).to include("Result: ")
      expect(output).not_to include("Survived mutations")
      expect(output).not_to include("Neutral mutations")
      expect(output).not_to include("Errored mutations")
    end

    it "renders the [TRUNCATED] line when summary.truncated? is true" do
      truncated_summary = Evilution::Result::Summary.new(results: [], duration: 0.0, truncated: true)
      output = described_class.new.call(truncated_summary)

      expect(output).to include("[TRUNCATED] Stopped early due to --fail-fast")
    end

    it "exercises the full section pipeline end-to-end on a comprehensive summary" do
      output = described_class.new.call(CliGoldenSummary.call)

      expect(output).to include("Survived mutations")
      expect(output).to include("Neutral mutations")
      expect(output).to include("Equivalent mutations")
      expect(output).to include("Unresolved mutations")
      expect(output).to include("Unparseable mutations")
      expect(output).to include("Errored mutations")
      expect(output).to include("Disabled mutations")
    end
  end
end
