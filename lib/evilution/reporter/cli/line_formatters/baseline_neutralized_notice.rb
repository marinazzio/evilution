# frozen_string_literal: true

require_relative "../line_formatters"
require_relative "../../../baseline"

# A survivor covered by a spec file that was already red is recorded neutral
# and drops out of the score. When the file was red for a reason of its own --
# the baseline process, not the spec -- those neutrals are survivors nobody
# sees, and the run prints full marks. So the score never goes out without
# saying how many survivors went that way, for which spec file, and why it
# was red.
class Evilution::Reporter::CLI::LineFormatters::BaselineNeutralizedNotice
  DETAIL_INDENT = "    "

  def initialize(failure_formatter: Evilution::Baseline::FailureFormatter.new)
    @failure_formatter = failure_formatter
  end

  def format(summary)
    neutralizations = summary.baseline_neutralizations
    return nil if neutralizations.empty?

    neutralizations.flat_map { |neutralization| [headline(neutralization), *detail(neutralization)] }.join("\n")
  end

  private

  def headline(neutralization)
    count = neutralization.count
    subject = count == 1 ? "1 survivor" : "#{count} survivors"
    caveat = count == 1 ? "it may be a real gap" : "they may be real gaps"
    "! #{subject} reclassified neutral because baseline failed#{spec_files(neutralization)}; #{caveat}."
  end

  def spec_files(neutralization)
    names = neutralization.spec_file ? [neutralization.spec_file] : neutralization.failures.map(&:spec_file)
    names.empty? ? "" : " for #{names.join(", ")}"
  end

  # One spec file's detail sits straight under the headline that names it;
  # several are each put under their own name.
  def detail(neutralization)
    failures = neutralization.failures
    return failure_lines(failures.first, DETAIL_INDENT) if failures.length == 1

    failures.flat_map do |failure|
      ["#{DETAIL_INDENT}#{failure.spec_file}:", *failure_lines(failure, "#{DETAIL_INDENT}  ")]
    end
  end

  def failure_lines(failure, indent)
    @failure_formatter.call(failure).map { |line| "#{indent}#{line}" }
  end
end
