# frozen_string_literal: true

require_relative "../baseline"

# The lines that say why a spec file was red in the baseline, shared by the
# warning printed during the run and the note in the final report.
class Evilution::Baseline::FailureFormatter
  NO_DETAIL = "no failure detail was captured"

  def call(failure)
    lines = error_lines(failure) + failure.examples.map { |example| example_line(example) }
    remainder = failure.example_count - failure.examples.length
    lines << "... and #{remainder} more failing" if remainder.positive?
    lines.empty? ? [NO_DETAIL] : lines
  end

  private

  def error_lines(failure)
    failure.error ? failure.error.lines.map(&:chomp) : []
  end

  def example_line(example)
    line = [example.id, example.description].reject(&:empty?).join(" ")
    example.message.empty? ? line : "#{line} -- #{example.message}"
  end
end
