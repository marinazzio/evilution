# frozen_string_literal: true

require_relative "../integration"

class Evilution::Integration::MinitestCrashDetector
  def initialize
    reset
  end

  def start
    # Required by Minitest reporter interface
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

  def record(result)
    result.failures.each do |failure|
      if failure.is_a?(::Minitest::UnexpectedError)
        @crashes << failure.error
      elsif failure.is_a?(::Minitest::Assertion)
        @assertion_failures += 1
      end
    end
  end

  def has_assertion_failure? # rubocop:disable Naming/PredicatePrefix
    @assertion_failures.positive?
  end

  def has_crash? # rubocop:disable Naming/PredicatePrefix
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
end
