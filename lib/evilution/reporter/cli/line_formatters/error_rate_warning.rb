# frozen_string_literal: true

require_relative "../line_formatters"

# EV-nrgw / GH #1168: Score is `killed / score_denominator` where
# `score_denominator = total - errors - neutral - equivalent - unresolved -
# unparseable` — errors are excluded from the denominator entirely. A run
# can read PASS at 100% while 16 of 19 mutations silently errored. This
# formatter surfaces a warning right under the metrics block when the error
# rate crosses the threshold so the silent failure mode becomes loud.
class Evilution::Reporter::CLI::LineFormatters::ErrorRateWarning
  DEFAULT_THRESHOLD = 0.25

  def initialize(threshold: DEFAULT_THRESHOLD)
    @threshold = threshold
  end

  def format(summary)
    return nil if summary.total.zero?
    return nil if summary.errors.zero?

    rate = summary.errors.to_f / summary.total
    return nil if rate <= @threshold

    pct = (rate * 100).round(1)
    "! High error rate: #{summary.errors}/#{summary.total} (#{pct}%) mutations errored — " \
      "score may be unreliable. See the \"Errored mutations:\" section for the underlying cause."
  end
end
