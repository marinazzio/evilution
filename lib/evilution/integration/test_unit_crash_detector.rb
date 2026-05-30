# frozen_string_literal: true

require_relative "../integration"

# Test::Unit analog of Evilution::Integration::MinitestCrashDetector. Tracks
# whether a Test::Unit test run produced only crashes (exceptions captured as
# Test::Unit::Error) vs assertion failures (Test::Unit::Failure). When only
# crashes occur, the mutation result is classified :error rather than :killed
# — see classify_status / Result::MutationResult.
#
# Hook the detector into a Test::Unit::TestResult via .attach(result), or
# call #record(fault) directly when iterating a finished result's #faults.
class Evilution::Integration::TestUnitCrashDetector
  def initialize
    reset
  end

  def reset
    @assertion_failures = 0
    @crashes = []
  end

  def attach(test_result)
    require "test/unit/testresult"
    test_result.add_listener(Test::Unit::TestResult::FAULT) { |fault| record(fault) }
  end

  def record(fault)
    if fault.is_a?(Test::Unit::Error)
      @crashes << fault.exception
    elsif fault.is_a?(Test::Unit::Failure)
      @assertion_failures += 1
    end
  end

  def passed?
    @assertion_failures.zero? && @crashes.empty?
  end

  def assertion_failure?
    @assertion_failures.positive?
  end

  def crashed?
    @crashes.any?
  end

  def only_crashes?
    @crashes.any? && @assertion_failures.zero?
  end

  def unique_crash_classes
    @crashes.map { |e| e.class.name }.uniq
  end

  def crash_summary
    return nil if @crashes.empty?

    "#{unique_crash_classes.join(", ")} (#{@crashes.length} crash#{"es" unless @crashes.length == 1})"
  end
end
