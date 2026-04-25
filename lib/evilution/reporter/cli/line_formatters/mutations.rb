# frozen_string_literal: true

require_relative "../line_formatters"

class Evilution::Reporter::CLI::LineFormatters::Mutations
  def format(summary)
    parts = "Mutations: #{summary.total} total, #{summary.killed} killed, " \
            "#{summary.survived} survived, #{summary.timed_out} timed out"
    parts += ", #{summary.neutral} neutral" if summary.neutral.positive?
    parts += ", #{summary.equivalent} equivalent" if summary.equivalent.positive?
    parts += ", #{summary.unresolved} unresolved" if summary.unresolved.positive?
    parts += ", #{summary.unparseable} unparseable" if summary.unparseable.positive?
    parts += ", #{summary.skipped} skipped" if summary.skipped.positive?
    parts
  end
end
