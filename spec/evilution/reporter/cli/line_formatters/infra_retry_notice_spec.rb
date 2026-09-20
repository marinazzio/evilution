# frozen_string_literal: true

RSpec.describe Evilution::Reporter::CLI::LineFormatters::InfraRetryNotice do
  subject(:formatter) { described_class.new }

  def summary_with(infra_retried)
    instance_double(Evilution::Result::Summary, infra_retried: infra_retried)
  end

  describe "#format" do
    it "returns nil when nothing had to be re-run" do
      expect(formatter.format(summary_with(0))).to be_nil
    end

    it "reports a single re-run mutation" do
      expect(formatter.format(summary_with(1))).to eq(
        "! 1 mutation hit infrastructure errors under parallel workers; re-ran it serially."
      )
    end

    it "reports several re-run mutations" do
      expect(formatter.format(summary_with(18))).to eq(
        "! 18 mutations hit infrastructure errors under parallel workers; re-ran them serially."
      )
    end
  end
end
