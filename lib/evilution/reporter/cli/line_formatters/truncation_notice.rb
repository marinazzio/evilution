# frozen_string_literal: true

require_relative "../line_formatters"

class Evilution::Reporter::CLI::LineFormatters::TruncationNotice
  def format(summary)
    return nil unless summary.truncated?

    "[TRUNCATED] Stopped early due to --fail-fast"
  end
end
