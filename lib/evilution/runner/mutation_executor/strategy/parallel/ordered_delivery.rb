# frozen_string_literal: true

require_relative "../parallel"
require_relative "../../../../infra_crash"

# Turns the compact results of a parallel run, which arrive in whatever order
# the workers finish, into the run's results in mutation order. A result is
# held back until every earlier mutation has one, then rebuilt, cached when the
# workers produced it in this run, has its mutation's sources dropped, goes
# through the neutralisation pipeline and on to the notifier, so what the
# notifier sees, where fail-fast cuts the run and what the reports list are the
# same as one mutation after another would give.
class Evilution::Runner::MutationExecutor::Strategy::Parallel::OrderedDelivery
  MEMORY_LOG_LABEL = "after batch"

  attr_reader :results

  # `log_every` is how many results go by between two memory logs.
  def initialize(mutations:, packer:, cache:, pipeline:, notifier:, baseline_result:, diagnostics:, log_every:)
    @mutations = mutations
    @packer = packer
    @cache = cache
    @pipeline = pipeline
    @notifier = notifier
    @baseline_result = baseline_result
    @diagnostics = diagnostics
    @log_every = log_every
    @pending = {}
    @results = []
    @truncated = false
  end

  def truncated?
    @truncated
  end

  # `fresh` says the workers produced the result in this run, as opposed to it
  # coming from the cache.
  # Results that arrive after the run was truncated are kept back for good.
  def accept(index, compact, fresh:)
    @pending[index] = [compact, fresh]
    release while !@truncated && @pending.key?(@results.length)
  end

  private

  def release
    mutation = @mutations[@results.length]
    compact, fresh = @pending.delete(@results.length)
    result = @packer.rebuild(mutation, compact)
    @cache.store(mutation, result) if fresh
    release_sources(mutation, result)
    record(@pipeline.call(result, baseline_result: @baseline_result))
  end

  # Sources are dropped as soon as a mutation has been judged, to keep a long
  # run's memory flat. A mutation the workers could not judge because of
  # infrastructure contention is re-run serially once the pool is done
  # (InfraRetry), which needs its sources, so it keeps them until then. The
  # neutralisation pipeline has not run yet here, so the crash is still a kill.
  def release_sources(mutation, result)
    return if Evilution::InfraCrash.class_name?(result.error_class)

    mutation.strip_sources!
  end

  def record(result)
    @results << result
    @truncated = @notifier.notify(result, @results.length) == :truncate
    log_memory
  end

  def log_memory
    return unless @diagnostics
    return unless log_due?

    @diagnostics.log_memory(MEMORY_LOG_LABEL, "#{@results.length} complete")
  end

  def log_due?
    @truncated || (@results.length % @log_every).zero? || @results.length == @mutations.length
  end
end
