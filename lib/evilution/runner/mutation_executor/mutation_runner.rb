# frozen_string_literal: true

require_relative "../mutation_executor"
require_relative "../../result/mutation_result"

class Evilution::Runner::MutationExecutor::MutationRunner
  # timeout_policy: answers the time limit for each mutation's test run.
  def initialize(cache:, isolator:, timeout_policy:)
    @cache = cache
    @isolator = isolator
    @timeout_policy = timeout_policy
  end

  def call(mutation, integration:)
    return unparseable_result(mutation) if mutation.unparseable?

    cached = @cache.fetch(mutation)
    return cached if cached

    test_command = ->(m) { integration.call(m) }
    limit = @timeout_policy.call(mutation)
    result = @isolator.call(mutation: mutation, test_command: test_command, timeout: limit)
    result = result.with_time_limit(limit) if result.timeout?
    @cache.store(mutation, result)
    result
  end

  private

  def unparseable_result(mutation)
    Evilution::Result::MutationResult.new(mutation: mutation, status: :unparseable)
  end
end
