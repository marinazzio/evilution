# frozen_string_literal: true

require_relative "../line_formatters"

class Evilution::Reporter::CLI::LineFormatters::Duration
  def format(summary)
    "Duration: #{Kernel.format("%.2f", summary.duration)}s"
  end
end
