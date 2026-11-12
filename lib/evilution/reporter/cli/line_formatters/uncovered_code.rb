# frozen_string_literal: true

require_relative "../line_formatters"

# A run aimed at lines that hold no subject generates nothing for them, and
# its report alone reads like a run that found nothing to mutate. The warning
# printed while the run starts says why, but it is easily lost above the
# progress output; this line repeats where in the report itself, next to the
# mutation count it explains.
class Evilution::Reporter::CLI::LineFormatters::UncoveredCode
  def format(summary)
    return nil unless summary.uncovered_code?

    listing = summary.uncovered_code.map { |entry| "    #{entry[:file]}:#{entry[:lines].join(", ")}" }.join("\n")
    "! Targeted lines hold code outside every subject — no mutations were generated for them:\n#{listing}"
  end
end
