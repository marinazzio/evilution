# frozen_string_literal: true

require_relative "../item_formatters"

class Evilution::Reporter::CLI::ItemFormatters::CoverageGap
  def format(gap)
    location = "#{gap.file_path}:#{gap.line}"
    "#{format_header(gap, location)}\n#{format_body(gap)}"
  end

  private

  def format_header(gap, location)
    return "  #{gap.primary_operator}: #{location} (#{gap.subject_name})" if gap.single?

    "  #{location} (#{gap.subject_name}) [#{gap.count} mutations: #{gap.operator_names.join(", ")}]"
  end

  def format_body(gap)
    body = gap.mutation_results.first.mutation.unified_diff || gap.primary_diff
    body.split("\n").map { |l| "    #{l}" }.join("\n")
  end
end
