# frozen_string_literal: true

require_relative "../cli"
require_relative "line_formatters/truncation_notice"
require_relative "line_formatters/result_line"

class Evilution::Reporter::CLI::Trailer
  DEFAULT_LINES = [
    Evilution::Reporter::CLI::LineFormatters::TruncationNotice.new,
    Evilution::Reporter::CLI::LineFormatters::ResultLine.new
  ].freeze

  def initialize(lines: DEFAULT_LINES)
    @lines = lines
  end

  def call(summary)
    @lines.filter_map { |line| line.format(summary) }
  end
end
