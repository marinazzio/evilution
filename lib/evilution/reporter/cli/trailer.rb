# frozen_string_literal: true

require_relative "../cli"
require_relative "line_formatters/truncation_notice"
require_relative "line_formatters/result_line"
require_relative "line_formatters/feedback_footer"

class Evilution::Reporter::CLI::Trailer
  def self.default_lines(min_score: nil)
    [
      Evilution::Reporter::CLI::LineFormatters::TruncationNotice.new,
      Evilution::Reporter::CLI::LineFormatters::ResultLine.new(min_score: min_score),
      Evilution::Reporter::CLI::LineFormatters::FeedbackFooter.new
    ]
  end

  DEFAULT_LINES = default_lines.freeze

  def initialize(lines: nil, min_score: nil)
    @lines = lines || self.class.default_lines(min_score: min_score)
  end

  def call(summary)
    @lines.filter_map { |line| line.format(summary) }
  end
end
