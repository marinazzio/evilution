# frozen_string_literal: true

require_relative "../mutation_executor"

# A run in two batches: first every subject's sentinel (see ProbeFirst), then
# the other mutations, once the probe knows which subjects no test exercises
# and the runless verdict can report their mutations without a run. Each
# batch is run by the block, as a strategy runs a whole run, with a notifier
# that numbers its results after the first batch's, so progress, fail-fast and
# the logs see one run. The results come back in the order the mutations came
# in.
#
# The second batch waits for the slowest sentinel: a parallel run's workers
# idle at the end of the first batch.
class Evilution::Runner::MutationExecutor::ProbeFirstRun
  # The run's notifier as one batch sees it: started and finished once for the
  # whole run, here, and counting on from the results reported before.
  class Continuation
    def initialize(notifier, offset)
      @notifier = notifier
      @offset = offset
    end

    def start(_total); end

    def finish; end

    def notify(result, index)
      @notifier.notify(result, @offset + index)
    end
  end

  def initialize(probe:, notifier:)
    @probe = probe
    @notifier = notifier
  end

  def call(mutations, &run_batch)
    sentinels, rest = @probe.split(mutations)
    @notifier.start(mutations.length)
    first = run_batch.call(sentinels, Continuation.new(@notifier, 0))
    first.results.each { |result| @probe.record(result) }
    second = first.truncated ? nil : run_batch.call(rest, Continuation.new(@notifier, first.results.length))
    @notifier.finish
    merge(mutations, [first, second].compact)
  end

  private

  def merge(mutations, executions)
    position = mutations.each_with_index.to_h
    Evilution::Runner::MutationExecutor::ExecutionResult.new(
      results: executions.flat_map(&:results).sort_by { |result| position.fetch(result.mutation) },
      truncated: executions.any?(&:truncated),
      infra_retried: executions.sum(&:infra_retried),
      worker_stats: executions.flat_map(&:worker_stats)
    )
  end
end
