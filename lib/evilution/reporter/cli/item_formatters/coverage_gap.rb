# frozen_string_literal: true

require_relative "../item_formatters"

class Evilution::Reporter::CLI::ItemFormatters::CoverageGap
  def format(gap)
    location = "#{gap.file_path}:#{gap.line}"
    header = if gap.single?
               "  #{gap.primary_operator}: #{location} (#{gap.subject_name})"
             else
               operators = gap.operator_names.join(", ")
               "  #{location} (#{gap.subject_name}) [#{gap.count} mutations: #{operators}]"
             end
    body = gap.mutation_results.first.mutation.unified_diff || gap.primary_diff
    indented = body.split("\n").map { |l| "    #{l}" }.join("\n")
    "#{header}\n#{indented}"
  end
end
