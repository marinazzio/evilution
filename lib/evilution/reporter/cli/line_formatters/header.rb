# frozen_string_literal: true

require_relative "../line_formatters"
require_relative "../../../version"

class Evilution::Reporter::CLI::LineFormatters::Header
  def format(_summary)
    "Evilution v#{Evilution::VERSION} — Mutation Testing Results"
  end
end
