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

  # known_failures_only: every example that failed was already failing in the
  # baseline. Still a failed run, but flagged, so it is not taken for a kill.
  def from_run(status, command, detector, examples_loaded: nil, known_failures_only: false)
    return { passed: true, test_command: command } if status.zero?
    # Before the crash check: an example that was already failing may fail by
    # raising now, and a crash in it is no more a kill than its failure was.
    return { passed: false, known_failures_only: true, test_command: command } if known_failures_only

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

    # Nonzero exit + zero examples loaded = the spec file did not register any
    # examples (load error, autoload mismatch, etc.), so nothing ran against
    # the mutation. Surfacing this as a generic fail would let classify_status
    # fall through to its :killed default and silently inflate the kill count
    # even though no example ever observed the mutation (EV-720r: macOS Rails
    # users hit autoload / fail_if_no_examples paths that yielded killed=100%
    # with empty worker output). Note: this checks LOADED count, not executed
    # count — filters/skip/--fail-fast can leave loaded > executed, but the
    # "spec failed to load entirely" case is the failure mode this guard targets.
    if !examples_loaded.nil? && examples_loaded.zero?
      return {
        passed: false,
        error: "RSpec exited #{status} but loaded 0 examples — no examples ran against the mutation. " \
               "Likely the spec file failed to load, --spec was misrouted, or RSpec is configured " \
               "with fail_if_no_examples. The mutation cannot be counted as killed.",
        test_command: command
      }
    end

    { passed: false, test_command: command }
  end
end
