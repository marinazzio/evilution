# frozen_string_literal: true

require_relative "../line_formatters"

class Evilution::Reporter::CLI::LineFormatters::PeakMemory
  def format(summary)
    peak = summary.peak_memory_mb
    return nil unless peak

    Kernel.format("Peak memory: %<mb>.1f MB", mb: peak)
  end
end
