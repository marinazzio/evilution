# frozen_string_literal: true

require_relative "../item_formatters"

class Evilution::Reporter::CLI::ItemFormatters::CoverageGap
  def format(gap)
    location = "#{gap.file_path}:#{gap.line}"
    "#{format_header(gap, location)}\n#{format_body(gap)}"
  end

  private

  def format_header(gap, location)
    return "  #{gap.primary_operator}: #{location} (#{gap.subject_name})#{implied_note(gap)}" if gap.single?

    "  #{location} (#{gap.subject_name}) [#{gap.count} mutations: #{gap.operator_names.join(", ")}]" \
      "#{implied_note(gap)}"
  end

  # A survivor a probe-first sentinel implied did not run, so it is told apart
  # from one whose tests ran and missed.
  def implied_note(gap)
    implied = gap.implied_results
    return "" if implied.empty?

    share = implied.length == gap.count ? "" : "#{implied.length} "
    " (#{share}implied by #{implied.first.implied_by}, not run)"
  end

  def format_body(gap)
    body = gap.mutation_results.first.mutation.unified_diff || gap.primary_diff
    body.split("\n").map { |l| "    #{l}" }.join("\n")
  end
end
