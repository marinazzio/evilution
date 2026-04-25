# frozen_string_literal: true

require_relative "../line_formatters"
require_relative "../pct"

class Evilution::Reporter::CLI::LineFormatters::Score
  def initialize(pct: Evilution::Reporter::CLI::Pct.new)
    @pct = pct
  end

  def format(summary)
    "Score: #{@pct.format(summary.score)} (#{summary.killed}/#{summary.score_denominator})"
  end
end
