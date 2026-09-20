# frozen_string_literal: true

require_relative "../mutation_executor"
require_relative "neutralizer/infra_error"

# Re-runs, one at a time, the mutations a parallel pass could not judge because
# the test process crashed on infrastructure — a database lock, a statement
# timeout — rather than on the mutation itself.
#
# Those crashes are demoted to `:neutral` so they do not inflate the kill count
# (EV-toid / GH #814), which leaves the neutral bucket swinging with `--jobs`
# on identical input: the contention that causes them only exists while several
# workers run at once. Re-running them after the pool is done removes the
# contention, so the verdict matches what a serial run would have produced
# (EV-j0bv / GH #1607).
#
# Only mutations neutralised by an infra crash are re-run. A neutral from a
# failing baseline is a real statement about the spec, and re-running it would
# say the same thing again.
class Evilution::Runner::MutationExecutor::InfraRetry
  attr_reader :retried_count

  def initialize(runner:, pipeline:)
    @runner = runner
    @pipeline = pipeline
    @retried_count = 0
  end

  def call(results, baseline_result:, integration:)
    @retried_count = 0

    results.map do |result|
      next result unless retryable?(result)

      @retried_count += 1
      rerun(result, baseline_result: baseline_result, integration: integration)
    end
  end

  private

  def retryable?(result)
    Evilution::Runner::MutationExecutor::Neutralizer::InfraError.infra_neutral?(result)
  end

  # The parallel pass keeps the sources of a retryable mutation alive so it can
  # be applied again; they are released here, once it has been.
  def rerun(result, baseline_result:, integration:)
    mutation = result.mutation
    rerun_result = @runner.call(mutation, integration: integration)
    mutation.strip_sources!
    @pipeline.call(rerun_result, baseline_result: baseline_result)
  end
end
