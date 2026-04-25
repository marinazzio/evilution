# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/line_formatters/truncation_notice"

RSpec.describe Evilution::Reporter::CLI::LineFormatters::TruncationNotice do
  describe "#format" do
    it "returns nil when summary.truncated? is false" do
      expect(described_class.new.format(double("s", truncated?: false))).to be_nil
    end

    it "returns the notice line when summary.truncated? is true" do
      expect(described_class.new.format(double("s", truncated?: true))).to eq(
        "[TRUNCATED] Stopped early due to --fail-fast"
      )
    end
  end
end
