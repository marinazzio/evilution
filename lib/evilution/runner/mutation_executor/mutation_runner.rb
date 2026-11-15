# frozen_string_literal: true

require_relative "../mutation_executor"
require_relative "../../result/mutation_result"
require_relative "timed_run"

class Evilution::Runner::MutationExecutor::MutationRunner
  # timeout_policy: answers the time limit for each mutation's test run.
  def initialize(cache:, isolator:, timeout_policy:)
    @cache = cache
    @timeout_policy = timeout_policy
    @timed_run = Evilution::Runner::MutationExecutor::TimedRun.new(isolator: isolator, timeout_policy: timeout_policy)
  end

  def call(mutation, integration:)
    return unparseable_result(mutation) if mutation.unparseable?

    cached = @cache.fetch(mutation, time_limit: @timeout_policy.final_limit(mutation))
    return cached if cached

    test_command = ->(m) { integration.call(m) }
    result = @timed_run.call(mutation, test_command)
    @cache.store(mutation, result)
    result
  end

  private

  def unparseable_result(mutation)
    Evilution::Result::MutationResult.new(mutation: mutation, status: :unparseable)
  end
end
