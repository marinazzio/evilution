# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli"
require "evilution/version"
require_relative "../../../support/fixtures/cli_golden_summary"

RSpec.describe Evilution::Reporter::CLI do
  describe "byte-for-byte output preservation" do
    # Golden fixtures use the literal token `EVILUTION_VERSION` where the
    # current `Evilution::VERSION` would appear, so version bumps don't force
    # us to regenerate the committed `.txt` files. The substitution happens
    # at read time, against the in-memory expected string only.
    def read_golden(name)
      File.read(File.expand_path("fixtures/#{name}", __dir__))
          .gsub("EVILUTION_VERSION", Evilution::VERSION)
    end

    it "matches the golden output for a complete summary" do
      summary = CliGoldenSummary.call
      output = described_class.new.call(summary)
      expect(output).to eq(read_golden("cli_golden_complete.txt"))
    end

    it "matches the golden output for a truncated summary" do
      summary = CliGoldenSummary.call(truncated: true)
      output = described_class.new.call(summary)
      expect(output).to eq(read_golden("cli_golden_truncated.txt"))
    end
  end
end
