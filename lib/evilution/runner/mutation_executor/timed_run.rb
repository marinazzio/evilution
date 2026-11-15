# frozen_string_literal: true

require_relative "../mutation_executor"

# Runs a mutation's tests under the limit its timeout policy gives it. A
# timeout the policy wants confirmed is not reported as it is: the mutation is
# run again under the confirmation limit, and that run's verdict stands, with
# the time of the first run added to what the mutation cost.
class Evilution::Runner::MutationExecutor::TimedRun
  def initialize(isolator:, timeout_policy:)
    @isolator = isolator
    @timeout_policy = timeout_policy
  end

  def call(mutation, test_command)
    result = run(mutation, test_command, @timeout_policy.call(mutation))
    return result unless result.timeout?

    confirmation = @timeout_policy.confirmation_limit(mutation)
    return result unless confirmation

    run(mutation, test_command, confirmation).after_adaptive_timeout(result.duration)
  end

  private

  def run(mutation, test_command, limit)
    result = @isolator.call(mutation: mutation, test_command: test_command, timeout: limit)
    result.timeout? ? result.with_time_limit(limit) : result
  end
end
