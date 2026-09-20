# frozen_string_literal: true

require_relative "../line_formatters"
require_relative "../pct"

# The threshold comes from the run's own configuration. Printing a verdict
# against a default the exit code did not share is what made a 0% score report
# `FAIL` and exit 0 (EV-39t1 / GH #1604); with no minimum configured the line
# states the score and says so, rather than implying a gate that is not armed.
class Evilution::Reporter::CLI::LineFormatters::ResultLine
  def initialize(pct: Evilution::Reporter::CLI::Pct.new, min_score: nil)
    @pct = pct
    @min_score = min_score
  end

  def format(summary)
    return unresolved_targets_line(summary) if summary.unresolved_targets?
    return no_threshold_line(summary) unless gate?

    pass_fail = summary.success?(min_score: @min_score) ? "PASS" : "FAIL"
    score_pct = @pct.format(summary.score)
    threshold_pct = @pct.format(@min_score)
    "Result: #{pass_fail} (score #{score_pct} #{pass_fail == "PASS" ? ">=" : "<"} #{threshold_pct})"
  end

  private

  # A minimum of zero passes every score, so it is not a gate either.
  def gate?
    !@min_score.nil? && @min_score.positive?
  end

  def no_threshold_line(summary)
    "Result: #{@pct.format(summary.score)} (no minimum score set)"
  end

  # The score covers only the files that resolved to a spec, so reporting it
  # against the threshold here would name the wrong problem.
  def unresolved_targets_line(summary)
    count = summary.unresolved_target_files.length
    subject = count == 1 ? "target file has" : "target files have"
    "Result: FAIL (#{count} #{subject} no resolvable spec)"
  end
end
