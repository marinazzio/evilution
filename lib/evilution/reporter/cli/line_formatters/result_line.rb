# frozen_string_literal: true

require_relative "../line_formatters"
require_relative "../pct"

class Evilution::Reporter::CLI::LineFormatters::ResultLine
  DEFAULT_MIN_SCORE = 0.8

  def initialize(pct: Evilution::Reporter::CLI::Pct.new, min_score: DEFAULT_MIN_SCORE)
    @pct = pct
    @min_score = min_score
  end

  def format(summary)
    pass_fail = summary.success?(min_score: @min_score) ? "PASS" : "FAIL"
    score_pct = @pct.format(summary.score)
    threshold_pct = @pct.format(@min_score)
    "Result: #{pass_fail} (score #{score_pct} #{pass_fail == "PASS" ? ">=" : "<"} #{threshold_pct})"
  end
end
