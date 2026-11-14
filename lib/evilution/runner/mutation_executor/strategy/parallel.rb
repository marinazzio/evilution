# frozen_string_literal: true

require_relative "../strategy"
require_relative "../../../parallel/work_queue"

class Evilution::Runner::MutationExecutor::Strategy::Parallel
  # Autoloaded rather than required at the bottom: ordered_delivery requires
  # this file, and requiring it while it is still loading is a circular
  # require, which Ruby warns about -- and a project that turns warnings into
  # exceptions loads this after its spec helper did so.
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

  def initialize(cache:, isolator:, packer:, pipeline:, notifier:, pool_factory:, config:, diagnostics: nil)
    @cache = cache
    @isolator = isolator
    @packer = packer
    @pipeline = pipeline
    @notifier = notifier
    @pool_factory = pool_factory
    @diagnostics = diagnostics
    @config = config
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

  # The cached results go in first; the rest run on one pool whose workers
  # live for the whole run and take the next mutation as soon as they are done
  # with the last, so a slow mutation holds up only its own worker.
  def run(mutations, delivery, integration)
    partition = @cache.partition(mutations, packer: @packer)
    partition.cached_results.each { |index, compact| delivery.accept(index, compact, fresh: false) }
    return [] if delivery.truncated? || partition.uncached_indices.empty?

    run_uncached(mutations, partition.uncached_indices, delivery, integration)
  end

  # Returns the pool's worker figures once every worker has been wound down.
  def run_uncached(mutations, uncached_indices, delivery, integration)
    pool = @pool_factory.call
    on_result = lambda do |position, raw|
      delivery.accept(uncached_indices[position], unpack_unfinished(raw), fresh: true)
      :stop if delivery.truncated?
    end
    pool.map(uncached_indices.map { |i| mutations[i] }, on_result: on_result) do |mutation, waited|
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
    result = @isolator.call(mutation: mutation, test_command: test_command, timeout: @config.timeout)
    @packer.compact(result).merge(queue_wait: waited)
  end

  def unpack_unfinished(result)
    return result unless result.is_a?(Evilution::Parallel::WorkQueue::Unfinished)

    case result.reason
    when :timeout then timeout_compact
    when :died then DIED_COMPACT
    when :unreadable then UNREADABLE_COMPACT
    end
  end

  # A :timeout result is cacheable, so give it a realistic duration: the stuck
  # worker exhausted the dispatcher's item_timeout (config.timeout * 2) before
  # being killed. A 0.0 here would be cached and skew summaries/reuse.
  def timeout_compact
    duration = @config.timeout * 2.0
    { status: :timeout, duration: duration, timings: { test_run: duration } }
  end
end
