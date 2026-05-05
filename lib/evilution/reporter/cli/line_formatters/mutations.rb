# frozen_string_literal: true

require_relative "../line_formatters"

class Evilution::Reporter::CLI::LineFormatters::Mutations
  OPTIONAL_FIELDS = %i[neutral equivalent unresolved unparseable skipped].freeze

  def format(summary)
    base_line(summary) + optional_sections(summary)
  end

  private

  def base_line(summary)
    "Mutations: #{summary.total} total, #{summary.killed} killed, " \
      "#{summary.survived} survived, #{summary.timed_out} timed out"
  end

  def optional_sections(summary)
    OPTIONAL_FIELDS.filter_map do |field|
      count = summary.public_send(field)
      ", #{count} #{field}" if count.positive?
    end.join
  end
end
