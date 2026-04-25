# frozen_string_literal: true

require_relative "../rspec"

class Evilution::Integration::RSpec::ResultBuilder
  def unresolved(mutation)
    {
      passed: false,
      unresolved: true,
      error: "no matching spec resolved for #{mutation.file_path}",
      test_command: "rspec (skipped: no spec resolved for #{mutation.file_path})"
    }
  end

  def unresolved_example(mutation)
    {
      passed: false,
      unresolved: true,
      error: "no matching example found for #{mutation.file_path}",
      test_command: "rspec (skipped: no matching example for #{mutation.file_path})"
    }
  end

  def from_run(status, command, detector)
    return { passed: true, test_command: command } if status.zero?

    if detector.only_crashes?
      classes = detector.unique_crash_classes
      return {
        passed: false,
        test_crashed: true,
        error: "test crashes: #{detector.crash_summary}",
        error_class: (classes.first if classes.length == 1),
        test_command: command
      }
    end

    { passed: false, test_command: command }
  end
end
