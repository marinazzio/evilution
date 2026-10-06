# frozen_string_literal: true

require_relative "../baseline"

# What a baseline run of one spec file sends back across the fork: whether it
# passed and, when it did not, enough to say why. A plain hash of strings and
# numbers, so it marshals over the pipe whatever the test framework is.
#
# The detail is bounded here, in the child: a spec file with a thousand failing
# examples has nothing more to say after the first few.
module Evilution::Baseline::Report
  MAX_EXAMPLES = 10
  MAX_MESSAGE_LENGTH = 300
  MESSAGE_LINES = 3
  ERROR_LINES = 5
  ELLIPSIS = "..."

  def self.build(passed:, failures: [], error: nil)
    {
      passed: passed ? true : false,
      failure_count: failures.length,
      failures: failures.first(MAX_EXAMPLES).map { |failure| example(failure) },
      error: error_excerpt(error)
    }
  end

  # A runner may still answer with a bare pass/fail.
  def self.from(outcome)
    outcome.is_a?(Hash) ? outcome : build(passed: outcome)
  end

  def self.example(failure)
    {
      id: failure[:id].to_s,
      description: failure[:description].to_s,
      message: truncate(lines_of(failure[:message]).first(MESSAGE_LINES).join(" "))
    }
  end
  private_class_method :example

  # Each line is cut on its own, so one long path does not cost the lines
  # after it.
  def self.error_excerpt(error)
    lines = lines_of(error).first(ERROR_LINES)
    lines.empty? ? nil : lines.map { |line| truncate(line) }.join("\n")
  end
  private_class_method :error_excerpt

  def self.lines_of(text)
    text.to_s.lines.map(&:strip).reject(&:empty?)
  end
  private_class_method :lines_of

  def self.truncate(text)
    return text if text.length <= MAX_MESSAGE_LENGTH

    "#{text[0, MAX_MESSAGE_LENGTH - ELLIPSIS.length]}#{ELLIPSIS}"
  end
  private_class_method :truncate
end
