# frozen_string_literal: true

require_relative "../integration"

class Evilution::Integration::CrashDetector
  def self.register_with_rspec
    ::RSpec::Core::Formatters.register self, :example_failed
  end

  def initialize(_output)
    reset
  end

  def reset
    @assertion_failures = 0
    @crashes = []
  end

  def example_failed(notification)
    exception = notification.example.exception

    if assertion_exception?(exception)
      @assertion_failures += 1
    else
      @crashes << exception
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

    types = @crashes.map { |e| e.class.name }.uniq
    "#{types.join(", ")} (#{@crashes.length} crash#{"es" unless @crashes.length == 1})"
  end

  private

  def assertion_exception?(exception)
    exception.is_a?(::RSpec::Expectations::ExpectationNotMetError) ||
      (defined?(::RSpec::Mocks::MockExpectationError) &&
        exception.is_a?(::RSpec::Mocks::MockExpectationError))
  end
end
