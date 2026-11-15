# frozen_string_literal: true

require_relative "../line_formatters"

class Evilution::Reporter::CLI::LineFormatters::Mutations
  OPTIONAL_FIELDS = %i[uncovered neutral equivalent unresolved unparseable skipped].freeze

  def format(summary)
    base_line(summary) + optional_sections(summary)
  end

  private

  def base_line(summary)
    "Mutations: #{summary.total} total, #{summary.killed} killed, " \
      "#{summary.survived} survived#{implied_note(summary)}, #{summary.timed_out} timed out"
  end

  # Survivors a probe-first sentinel implied are counted in survived, but did
  # not run, and can be wrong; the line says how many there are.
  def implied_note(summary)
    implied = summary.implied
    implied.positive? ? " (#{implied} implied, not run)" : ""
  end

  def optional_sections(summary)
    OPTIONAL_FIELDS.filter_map do |field|
      count = summary.public_send(field)
      ", #{count} #{field}" if count.positive?
    end.join
  end
end
