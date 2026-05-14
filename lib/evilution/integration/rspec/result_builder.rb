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

  def from_run(status, command, detector, examples_executed: nil)
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

    # Nonzero exit + zero examples = no observation of the mutation. Surfacing
    # this as a generic fail would let classify_status fall through to its
    # :killed default and silently inflate the kill count even though the
    # spec suite never actually ran a single example against the mutation
    # (EV-720r: macOS Rails users hit fail_if_no_examples / autoload issues
    # that yielded killed=100% with empty worker output).
    if !examples_executed.nil? && examples_executed.zero?
      return {
        passed: false,
        error: "RSpec exited #{status} but ran 0 examples — no examples ran against the mutation. " \
               "Likely the spec file failed to load, --spec was misrouted, or RSpec is configured " \
               "with fail_if_no_examples. The mutation cannot be counted as killed.",
        test_command: command
      }
    end

    { passed: false, test_command: command }
  end
end
