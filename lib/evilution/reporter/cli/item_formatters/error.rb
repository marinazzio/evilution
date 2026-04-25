# frozen_string_literal: true

require_relative "../item_formatters"

class Evilution::Reporter::CLI::ItemFormatters::Error
  def format(result)
    mutation = result.mutation
    header = "  #{mutation.operator_name}: #{mutation.file_path}:#{mutation.line}"
    return header unless result.error_message

    indented = result.error_message.lines.map { |line| "    #{line.chomp}" }.join("\n")
    "#{header}\n#{indented}"
  end
end
