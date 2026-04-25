# frozen_string_literal: true

require_relative "../cli"
require_relative "line_formatters/mutations"
require_relative "line_formatters/score"
require_relative "line_formatters/duration"
require_relative "line_formatters/efficiency"
require_relative "line_formatters/peak_memory"

class Evilution::Reporter::CLI::MetricsBlock
  DEFAULT_LINES = [
    Evilution::Reporter::CLI::LineFormatters::Mutations.new,
    Evilution::Reporter::CLI::LineFormatters::Score.new,
    Evilution::Reporter::CLI::LineFormatters::Duration.new,
    Evilution::Reporter::CLI::LineFormatters::Efficiency.new,
    Evilution::Reporter::CLI::LineFormatters::PeakMemory.new
  ].freeze

  def initialize(lines: DEFAULT_LINES)
    @lines = lines
  end

  def call(summary)
    @lines.filter_map { |line| line.format(summary) }
  end
end
