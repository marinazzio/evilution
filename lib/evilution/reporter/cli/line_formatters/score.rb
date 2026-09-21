# frozen_string_literal: true

require_relative "../line_formatters"
require_relative "../pct"

# The score covers only the mutations that got a verdict. Where a run left some
# out — neutral, unresolved, equivalent, errored — full marks over a fraction of
# it reads as a verdict on the whole, so the line says how much it covered
# (EV-5pob / GH #1606).
class Evilution::Reporter::CLI::LineFormatters::Score
  def initialize(pct: Evilution::Reporter::CLI::Pct.new)
    @pct = pct
  end

  def format(summary)
    "Score: #{@pct.format(summary.score)} (#{counts(summary)})"
  end

  private

  def counts(summary)
    verified = summary.score_denominator
    pair = "#{summary.killed}/#{verified}"
    return pair if verified == summary.total

    "#{pair} verified of #{summary.total} mutations#{neutral_note(summary)}"
  end

  def neutral_note(summary)
    summary.neutral.positive? ? ", #{summary.neutral} neutral" : ""
  end
end
