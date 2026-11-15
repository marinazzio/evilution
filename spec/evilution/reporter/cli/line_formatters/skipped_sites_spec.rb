# frozen_string_literal: true

RSpec.describe Evilution::Reporter::CLI::LineFormatters::SkippedSites do
  subject(:formatter) { described_class.new }

  def summary_with(skipped_sites)
    instance_double(Evilution::Result::Summary, skipped_sites: skipped_sites.freeze)
  end

  describe "#format" do
    it "returns nil when no preset skipped anything" do
      expect(formatter.format(summary_with({}))).to be_nil
    end

    it "names each preset with the mutations it skipped" do
      expect(formatter.format(summary_with(logging: 3, error_messages: 12)))
        .to eq("Skipped sites: logging 3, error_messages 12")
    end
  end
end
