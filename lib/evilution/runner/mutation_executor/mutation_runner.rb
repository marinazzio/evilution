# frozen_string_literal: true

require_relative "../mutation_executor"
require_relative "../../result/mutation_result"
require_relative "runless_verdict"

class Evilution::Runner::MutationExecutor::MutationRunner
  # timeout_policy: answers the time limit for each mutation's test run.
  # runless: the verdict a mutation gets without a run, when it has one.
  def initialize(cache:, isolator:, timeout_policy:,
                 runless: Evilution::Runner::MutationExecutor::RunlessVerdict.new)
    @cache = cache
    @isolator = isolator
    @timeout_policy = timeout_policy
    @runless = runless
  end

  def call(mutation, integration:)
    runless = @runless.call(mutation)
    return runless if runless

    cached = @cache.fetch(mutation)
    return cached if cached

    test_command = ->(m) { integration.call(m) }
    limit = @timeout_policy.call(mutation)
    result = @isolator.call(mutation: mutation, test_command: test_command, timeout: limit)
    result = result.with_time_limit(limit) if result.timeout?
    @cache.store(mutation, result)
    result
  end
end
