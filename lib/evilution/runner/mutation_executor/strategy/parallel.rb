# frozen_string_literal: true

require_relative "../strategy"
require_relative "../../../parallel/work_queue"
require_relative "../timeout_policy"
require_relative "../runless_verdict"

class Evilution::Runner::MutationExecutor::Strategy::Parallel
  # Autoloaded rather than required at the bottom, which would require this
  # file again while it is still loading (see TimeoutPolicy).
  autoload :OrderedDelivery, File.expand_path("parallel/ordered_delivery", __dir__)

  # Compact result for a worker that exited unexpectedly (:error is not cached,
  # so the 0.0 duration is never persisted).
  DIED_COMPACT = {
    status: :error,
    duration: 0.0,
    error_message: "worker process exited unexpectedly",
    error_class: "Evilution::Error"
  }.freeze

  # Compact result for an item whose worker sent a frame that was not its own:
  # the worker was given up, and what it had to say about the item with it.
  UNREADABLE_COMPACT = {
    status: :error,
    duration: 0.0,
    error_message: "worker's result could not be read; the worker was replaced",
    error_class: "Evilution::Error"
  }.freeze

  # pool_factory: called with the pool's item timeout, the backstop for a
  # worker that stops answering. timeout_policy: the limit each mutation runs
  # under; the configured timeout for every one of them when not given.
  # runless: the verdict a mutation gets without a run, when it has one.
  def initialize(cache:, isolator:, packer:, pipeline:, notifier:, pool_factory:, config:, diagnostics: nil,
                 timeout_policy: nil, runless: Evilution::Runner::MutationExecutor::RunlessVerdict.new)
    @cache = cache
    @isolator = isolator
    @packer = packer
    @pipeline = pipeline
    @notifier = notifier
    @pool_factory = pool_factory
    @diagnostics = diagnostics
    @config = config
    @timeout_policy = timeout_policy || Evilution::Runner::MutationExecutor::TimeoutPolicy::Fixed.new(config.timeout)
    @runless = runless
  end

  def call(mutations, baseline_result:, integration:)
    @notifier.start(mutations.length)
    delivery = build_delivery(mutations, baseline_result)
    worker_stats = Evilution::Parallel::WorkQueue::WorkerStat.aggregate(run(mutations, delivery, integration))

    log_worker_diagnostics(worker_stats)
    @notifier.finish
    Evilution::Runner::MutationExecutor::ExecutionResult.new(
      results: delivery.results, truncated: delivery.truncated?, worker_stats: worker_stats
    )
  end

  private

  def build_delivery(mutations, baseline_result)
    OrderedDelivery.new(
      mutations: mutations, packer: @packer, cache: @cache, pipeline: @pipeline, notifier: @notifier,
      baseline_result: baseline_result, diagnostics: @diagnostics, log_every: @config.jobs
    )
  end

  # The cached results, and the verdicts given without a run, go in first;
  # the rest run on one pool whose workers
  # live for the whole run and take the next mutation as soon as they are done
  # with the last, so a slow mutation holds up only its own worker.
  def run(mutations, delivery, integration)
    partition = @cache.partition(mutations, packer: @packer, runless: @runless)
    partition.cached_results.each { |index, compact| delivery.accept(index, compact, fresh: false) }
    return [] if delivery.truncated? || partition.uncached_indices.empty?

    run_uncached(mutations, partition.uncached_indices, delivery, integration)
  end

  # Returns the pool's worker figures once every worker has been wound down.
  def run_uncached(mutations, uncached_indices, delivery, integration)
    uncached = uncached_indices.map { |i| mutations[i] }
    item_timeout = @timeout_policy.item_timeout(uncached)
    pool = @pool_factory.call(item_timeout)
    on_result = lambda do |position, raw|
      delivery.accept(uncached_indices[position], unpack_unfinished(raw, item_timeout), fresh: true)
      :stop if delivery.truncated?
    end
    pool.map(uncached, on_result: on_result) do |mutation, waited|
      run_in_worker(mutation, integration, waited)
    end
    pool.worker_stats
  end

  def log_worker_diagnostics(worker_stats)
    return unless @diagnostics

    @diagnostics.log_worker_stats(worker_stats)
  end

  # Runs in the worker. `waited` is how long the mutation sat between the
  # dispatcher sending it and this worker starting it, nil when not measured.
  def run_in_worker(mutation, integration, waited)
    test_command = ->(m) { integration.call(m) }
    limit = @timeout_policy.call(mutation)
    result = @isolator.call(mutation: mutation, test_command: test_command, timeout: limit)
    result = result.with_time_limit(limit) if result.timeout?
    @packer.compact(result).merge(queue_wait: waited)
  end

  def unpack_unfinished(result, item_timeout)
    return result unless result.is_a?(Evilution::Parallel::WorkQueue::Unfinished)

    case result.reason
    when :timeout then timeout_compact(item_timeout)
    when :died then DIED_COMPACT
    when :unreadable then UNREADABLE_COMPACT
    end
  end

  # A :timeout result is cacheable, so give it a realistic duration: the stuck
  # worker exhausted the dispatcher's item_timeout before being killed. A 0.0
  # here would be cached and skew summaries/reuse. Only a pool that has an
  # item timeout times an item out, so it is never nil here.
  def timeout_compact(item_timeout)
    { status: :timeout, duration: item_timeout, timings: { test_run: item_timeout }, time_limit: item_timeout }
  end
end
