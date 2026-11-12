# frozen_string_literal: true

RSpec.describe Evilution::Reporter::CLI::LineFormatters::UncoveredCode do
  subject(:formatter) { described_class.new }

  def summary_with(uncovered_code)
    instance_double(
      Evilution::Result::Summary,
      uncovered_code: uncovered_code.freeze,
      uncovered_code?: !uncovered_code.empty?
    )
  end

  describe "#format" do
    it "returns nil when every targeted line belongs to a subject" do
      expect(formatter.format(summary_with([]))).to be_nil
    end

    it "names each file and the lines no mutation could target" do
      uncovered = [
        { file: "app/models/vote.rb", lines: %w[9] },
        { file: "app/models/order.rb", lines: %w[2-4 9] }
      ]

      expect(formatter.format(summary_with(uncovered))).to eq(
        "! Targeted lines hold code outside every subject — no mutations were generated for them:\n    " \
        "app/models/vote.rb:9\n    " \
        "app/models/order.rb:2-4, 9"
      )
    end
  end
end
