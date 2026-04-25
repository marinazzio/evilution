# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/line_formatters/header"
require "evilution/version"

RSpec.describe Evilution::Reporter::CLI::LineFormatters::Header do
  describe "#format" do
    it "returns the version + branding line" do
      summary = double("summary")
      expect(described_class.new.format(summary)).to eq(
        "Evilution v#{Evilution::VERSION} — Mutation Testing Results"
      )
    end
  end
end
