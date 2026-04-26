# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/trailer"
require "evilution/feedback"
require "evilution/feedback/messages"

RSpec.describe Evilution::Reporter::CLI::Trailer do
  describe "#call" do
    it "returns nil-filtered lines from configured formatters" do
      summary = double("summary")
      f1 = double("f1")
      allow(f1).to receive(:format).with(summary).and_return(nil)
      f2 = double("f2")
      allow(f2).to receive(:format).with(summary).and_return("trailer-line")
      trailer = described_class.new(lines: [f1, f2])
      expect(trailer.call(summary)).to eq(["trailer-line"])
    end
  end

  describe "DEFAULT_LINES" do
    it "is a frozen array containing TruncationNotice, ResultLine and FeedbackFooter instances" do
      expect(described_class::DEFAULT_LINES).to be_frozen
      classes = described_class::DEFAULT_LINES.map(&:class)
      expect(classes).to eq([Evilution::Reporter::CLI::LineFormatters::TruncationNotice,
                             Evilution::Reporter::CLI::LineFormatters::ResultLine,
                             Evilution::Reporter::CLI::LineFormatters::FeedbackFooter])
    end
  end
end

RSpec.describe Evilution::Reporter::CLI::Trailer, "feedback footer" do
  unless defined?(TrailerFrictionSummary)
    TrailerFrictionSummary = Struct.new(
      :errors, :unparseable, :unresolved, :truncated?, :results,
      :total, :killed, :survived, :equivalent, :neutral, :timed_out,
      :duration, :score, :skipped, :disabled_mutations,
      keyword_init: true
    ) do
      def initialize(errors: 0, unparseable: 0, unresolved: 0)
        super(
          errors: errors, unparseable: unparseable, unresolved: unresolved,
          truncated?: false, results: [], total: 0, killed: 0, survived: 0,
          equivalent: 0, neutral: 0, timed_out: 0, duration: 0.0, score: 0.0,
          skipped: 0, disabled_mutations: []
        )
      end

      def success?(min_score:)
        score >= min_score
      end
    end
  end

  it "omits feedback footer on clean summary" do
    lines = described_class.new.call(TrailerFrictionSummary.new)
    expect(lines.join("\n")).not_to include(Evilution::Feedback::DISCUSSION_URL)
  end

  it "includes feedback footer when errors > 0" do
    lines = described_class.new.call(TrailerFrictionSummary.new(errors: 1))
    expect(lines.join("\n")).to include(Evilution::Feedback::Messages.cli_footer)
  end

  it "includes feedback footer when unresolved > 0" do
    lines = described_class.new.call(TrailerFrictionSummary.new(unresolved: 1))
    expect(lines.join("\n")).to include(Evilution::Feedback::Messages.cli_footer)
  end

  it "includes feedback footer when unparseable > 0" do
    lines = described_class.new.call(TrailerFrictionSummary.new(unparseable: 1))
    expect(lines.join("\n")).to include(Evilution::Feedback::Messages.cli_footer)
  end
end
