# frozen_string_literal: true

require "evilution/reporter/cli/line_formatters/feedback_footer"
require "evilution/feedback/messages"

RSpec.describe Evilution::Reporter::CLI::LineFormatters::FeedbackFooter do
  unless defined?(FrictionSummary)
    FrictionSummary = Struct.new(:errors, :unparseable, :unresolved, keyword_init: true) do
      def initialize(errors: 0, unparseable: 0, unresolved: 0)
        super
      end
    end
  end

  let(:formatter) { described_class.new }

  it "returns nil when no friction signals" do
    expect(formatter.format(FrictionSummary.new)).to be_nil
  end

  it "returns the canonical footer line on friction" do
    expect(formatter.format(FrictionSummary.new(errors: 1))).to eq(Evilution::Feedback::Messages.cli_footer)
  end

  it "returns nil for a nil summary" do
    expect(formatter.format(nil)).to be_nil
  end
end
