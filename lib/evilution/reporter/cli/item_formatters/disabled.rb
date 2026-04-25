# frozen_string_literal: true

require_relative "../item_formatters"

class Evilution::Reporter::CLI::ItemFormatters::Disabled
  def format(mutation)
    "  #{mutation.operator_name}: #{mutation.file_path}:#{mutation.line}"
  end
end
