# frozen_string_literal: true

require_relative "../integration"
require_relative "known_failures"
require_relative "../infra_crash"

# Decides when a mutation's test run has seen enough to stop.
#
# A failure is decisive when it says something about the mutation: a test the
# baseline did not already see failing, and not a crash of the test
# infrastructure itself (which would say nothing whatever the mutation was).
# The first decisive failure latches the policy, and the integration stops its
# framework.
class Evilution::Integration::StopPolicy
  def initialize(enabled:, known_failures:)
    @enabled = enabled
    @known_failures = known_failures
    @stopped = false
  end

  # exception is nil for an assertion failure; a crash passes its exception.
  def decisive?(id:, exception: nil)
    return false if @known_failures.include?(id)
    return true if exception.nil?

    !Evilution::InfraCrash.class_name?(exception.class.name)
  end

  # Returns true, and latches, on each decisive failure recorded while
  # enabled; false otherwise.
  def record(id:, exception: nil)
    return false unless @enabled
    return false unless decisive?(id: id, exception: exception)

    @stopped = true
  end

  def stopped?
    @stopped
  end

  def reset
    @stopped = false if @enabled
  end

  # Null object for integrations given no policy. Frozen and shared, so it
  # never touches state: record and reset are no-ops.
  DISABLED = new(enabled: false, known_failures: Evilution::Integration::KnownFailures.new([])).freeze
end
