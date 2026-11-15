# frozen_string_literal: true

require_relative "../integration"
require_relative "stop_policy"
require_relative "rspec/example_ids"

class Evilution::Integration::CrashDetector
  def self.register_with_rspec
    ::RSpec::Core::Formatters.register self, :example_failed
  end

  # The run's stop policy. Left alone, the detector never stops a run: only a
  # mutation's own run is handed a policy that can.
  attr_writer :policy

  def initialize(_output)
    @policy = Evilution::Integration::StopPolicy::DISABLED
    reset
  end

  # The id of the run's first decisive failure (see StopPolicy#decisive?),
  # the example that killed the mutation; nil while there is none. Named
  # whether or not the policy stops the run there.
  attr_reader :killing_id

  def reset
    @assertion_failures = 0
    @crashes = []
    @raised_quit = false
    @killing_id = nil
  end

  # RSpec checks RSpec.world.wants_to_quit before each example and skips the
  # rest once it is up, which is how a decisive failure ends the run.
  def example_failed(notification)
    example = notification.example
    crash = tally(example.exception)
    id = Evilution::Integration::RSpec::ExampleIds.of(example)
    @killing_id ||= id if @policy.decisive?(id:, exception: crash)
    raise_quit if @policy.record(id:, exception: crash)
  end

  # Whether this run's flag went up because of this detector. A flag that was
  # already up, such as from RSpec's handler on the user's first Ctrl-C, is
  # not the detector's to take back down.
  def raised_quit?
    @raised_quit
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

  def raise_quit
    return if ::RSpec.world.wants_to_quit

    ::RSpec.world.wants_to_quit = true
    @raised_quit = true
  end

  # Counts the failure; returns its exception when it is a crash, nil when it
  # is an assertion failure.
  def tally(exception)
    if assertion_exception?(exception)
      @assertion_failures += 1
      nil
    else
      @crashes << exception
      exception
    end
  end

  def assertion_exception?(exception)
    exception.is_a?(::RSpec::Expectations::ExpectationNotMetError) ||
      (defined?(::RSpec::Mocks::MockExpectationError) &&
        exception.is_a?(::RSpec::Mocks::MockExpectationError))
  end
end
