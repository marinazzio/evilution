# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli"
require_relative "../../../support/fixtures/cli_golden_summary"

RSpec.describe Evilution::Reporter::CLI do
  describe "byte-for-byte output preservation" do
    it "matches the golden output for a complete summary" do
      summary = CliGoldenSummary.call
      output = described_class.new.call(summary)
      expected = File.read(
        File.expand_path("fixtures/cli_golden_complete.txt", __dir__)
      )
      expect(output).to eq(expected)
    end

    it "matches the golden output for a truncated summary" do
      summary = CliGoldenSummary.call(truncated: true)
      output = described_class.new.call(summary)
      expected = File.read(
        File.expand_path("fixtures/cli_golden_truncated.txt", __dir__)
      )
      expect(output).to eq(expected)
    end
  end
end
