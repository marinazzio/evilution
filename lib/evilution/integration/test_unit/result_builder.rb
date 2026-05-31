# frozen_string_literal: true

require_relative "../test_unit"

# Shapes the result Hash that flows back to Evilution::Result::MutationResult
# / classify_status. Three orthogonal flavours — pass/fail/crash, no tests
# executed, and unresolved spec — each have their own change axis (e.g. the
# no-tests-ran error string evolved separately as the test-unit framework
# diagnostic improved). Putting them behind a single object documents the
# contract and lets the integration class drop them.
module Evilution::Integration::TestUnit::ResultBuilder
  module_function

  def call(passed:, command:, detector:)
    if passed
      { passed: true, test_command: command }
    elsif detector.only_crashes?
      crash(command, detector)
    else
      { passed: false, test_command: command }
    end
  end

  def no_tests_ran(command)
    {
      passed: false,
      error: "no Test::Unit tests executed (0 test methods ran) — the resolved " \
             "spec registered no Test::Unit suite. Check --integration/--spec.",
      error_class: "Evilution::Error",
      test_command: command
    }
  end

  def unresolved(mutation_file_path)
    {
      passed: false,
      unresolved: true,
      error: "no matching test resolved for #{mutation_file_path}",
      test_command: "ruby -Itest (skipped: no test resolved for #{mutation_file_path})"
    }
  end

  def crash(command, detector)
    classes = detector.unique_crash_classes
    {
      passed: false,
      test_crashed: true,
      error: "test crashes: #{detector.crash_summary}",
      error_class: (classes.first if classes.length == 1),
      test_command: command
    }
  end
end
