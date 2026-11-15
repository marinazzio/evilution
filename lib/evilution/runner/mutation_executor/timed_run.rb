# frozen_string_literal: true

require_relative "../mutation_executor"
require_relative "isolated_run"

# Runs a mutation's tests under the limit its timeout policy gives it. A
# timeout the policy wants confirmed is not reported as it is: the mutation is
# run again under the confirmation limit, and that run's verdict stands, with
# the time of the first run added to what the mutation cost.
#
# Each run under a limit is an IsolatedRun, so a run whose tests the
# integration reordered and that timed out is run again in the defined order
# under the same limit before the confirmation is asked for: a mutation that
# times out every way is judged by a run in the defined order under the
# confirmation limit.
class Evilution::Runner::MutationExecutor::TimedRun
  def initialize(isolator:, timeout_policy:)
    @isolated_run = Evilution::Runner::MutationExecutor::IsolatedRun.new(isolator)
    @timeout_policy = timeout_policy
  end

  # integration: what runs the tests, answering #call(mutation) with the test
  # command (see IsolatedRun).
  def call(mutation, integration)
    result = @isolated_run.call(mutation, integration, @timeout_policy.call(mutation))
    return result unless result.timeout?

    confirmation = @timeout_policy.confirmation_limit(mutation)
    return result unless confirmation

    @isolated_run.call(mutation, integration, confirmation).after_adaptive_timeout(result.duration)
  end
end
