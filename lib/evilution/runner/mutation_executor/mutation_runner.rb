# frozen_string_literal: true

require_relative "../mutation_executor"
require_relative "../../result/mutation_result"
require_relative "runless_verdict"
require_relative "kill_history"
require_relative "timed_run"

class Evilution::Runner::MutationExecutor::MutationRunner
  # timeout_policy: answers the time limit for each mutation's test run.
  # runless: the verdict a mutation gets without a run, when it has one.
  # kill_history: the tests that killed earlier mutations of the run (see
  # KillHistory), handed to the integration so it can try them first.
  def initialize(cache:, isolator:, timeout_policy:,
                 runless: Evilution::Runner::MutationExecutor::RunlessVerdict.new,
                 kill_history: Evilution::Runner::MutationExecutor::KillHistory::NONE)
    @cache = cache
    @timeout_policy = timeout_policy
    @runless = runless
    @kill_history = kill_history
    @timed_run = Evilution::Runner::MutationExecutor::TimedRun.new(isolator: isolator, timeout_policy: timeout_policy)
  end

  def call(mutation, integration:)
    runless = @runless.call(mutation)
    return runless if runless

    cached = @cache.fetch(mutation, time_limit: @timeout_policy.final_limit(mutation))
    return remembered(mutation, cached) if cached

    remembered(mutation, run(mutation, integration))
  end

  private

  # The integration is told before the isolator runs, so a forked child
  # inherits what it was told.
  def run(mutation, integration)
    integration.prioritize(@kill_history.killers_for(mutation)) if integration.respond_to?(:prioritize)
    result = @timed_run.call(mutation, integration)
    @cache.store(mutation, result)
    result
  end

  def remembered(mutation, result)
    @kill_history.record(mutation, status: result.status, killing_test: result.killing_test)
    result
  end
end
