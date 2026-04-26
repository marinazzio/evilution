# frozen_string_literal: true

require_relative "../line_formatters"
require_relative "../../../feedback/detector"
require_relative "../../../feedback/messages"

class Evilution::Reporter::CLI::LineFormatters::FeedbackFooter
  def format(summary)
    return nil unless Evilution::Feedback::Detector.friction?(summary)

    Evilution::Feedback::Messages.cli_footer
  end
end
