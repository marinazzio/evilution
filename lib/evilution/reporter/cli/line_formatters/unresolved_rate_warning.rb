# frozen_string_literal: true

require_relative "../line_formatters"

# EV-z7f5 / GH #1325: unresolved mutations are excluded from
# `score_denominator`, so a run whose specs could not be auto-resolved
# collapses to a bare "Score: 0.00% (0/0)" that reads like a genuine
# mutation-quality failure. This formatter surfaces a loud, actionable
# warning when the unresolved rate is high — and a distinct message when
# the denominator hit zero (nothing was measured at all) — so the user
# knows to pass --spec instead of trusting the 0.0.
#
# Sibling of ErrorRateWarning (EV-nrgw / GH #1168).
class Evilution::Reporter::CLI::LineFormatters::UnresolvedRateWarning
  DEFAULT_THRESHOLD = 0.25

  def initialize(threshold: DEFAULT_THRESHOLD)
    @threshold = threshold
  end

  def format(summary)
    return nil if summary.total.zero?
    return nil if summary.unresolved.zero?

    rate = summary.unresolved.to_f / summary.total
    return nil if rate <= @threshold

    pct = (rate * 100).round(1)
    fraction = "#{summary.unresolved}/#{summary.total}"

    if summary.score_denominator.zero?
      "! No matching tests resolved: #{fraction} mutations unresolved — " \
        "no mutations were measured, so the score is not meaningful. " \
        "Pass --spec to point evilution at the test file(s)."
    else
      "! High unresolved rate: #{fraction} (#{pct}%) mutations had no matching " \
        "test — score may be unreliable. Pass --spec to point evilution at the test file(s)."
    end
  end
end
