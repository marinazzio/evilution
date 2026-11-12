# frozen_string_literal: true

require_relative "../integration"
require_relative "stop_policy"

class Evilution::Integration::MinitestCrashDetector
  # The run's stop policy. Left alone, the detector never stops a run: only a
  # mutation's own run is handed a policy that can.
  attr_writer :policy

  def initialize
    @policy = Evilution::Integration::StopPolicy::DISABLED
    reset
  end

  def start
    # Required by Minitest reporter interface
  end

  def prerecord(_klass, _name)
    # Required by Minitest::AbstractReporter (5.11+/6.x) before each test
  end

  def report
    # Required by Minitest reporter interface
  end

  def passed?
    @crashes.empty?
  end

  def reset
    @assertion_failures = 0
    @crashes = []
  end

  # UnexpectedError and Skip both subclass Assertion. A crash hands its
  # exception to the policy and an assertion failure nothing; a skip says
  # nothing about the mutant, so the policy never hears of it.
  def record(result)
    result.failures.each do |failure|
      if failure.is_a?(::Minitest::UnexpectedError)
        @crashes << failure.error
        @policy.record(id: test_id(result), exception: failure.error)
      elsif failure.is_a?(::Minitest::Assertion)
        @assertion_failures += 1
        @policy.record(id: test_id(result)) unless failure.is_a?(::Minitest::Skip)
      end
    end
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

  def crash_summary
    return nil if @crashes.empty?

    "#{unique_crash_classes.join(", ")} (#{@crashes.length} crash#{"es" unless @crashes.length == 1})"
  end

  def unique_crash_classes
    @crashes.map { |e| e.class.name }.uniq
  end

  private

  # Loaded here rather than with this file: TestIds lives under the Minitest
  # integration class, which requires this file before it is defined.
  def test_id(result)
    require_relative "minitest/test_ids"
    Evilution::Integration::Minitest::TestIds.of(result)
  end
end
