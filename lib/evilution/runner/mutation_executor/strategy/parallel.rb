# frozen_string_literal: true

require_relative "../strategy"
require_relative "../../../parallel/work_queue"
require_relative "../../../infra_crash"

class Evilution::Runner::MutationExecutor::Strategy::Parallel
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
    pool = @pool_factory.call
    state = { results: [], truncated: false, completed: 0 }
    worker_stats = Evilution::Parallel::WorkQueue::WorkerStat.aggregate(
      run_batches(mutations, pool, baseline_result, integration, state)
    )

    log_worker_diagnostics(worker_stats)
    @notifier.finish
    build_result(state, worker_stats)
  end

  private

  def run_batches(mutations, pool, baseline_result, integration, state)
    all_worker_stats = []
    mutations.each_slice(@config.jobs) do |batch|
      break if state[:truncated]

      batch_results = run_batch(batch, pool, integration)
      all_worker_stats.concat(pool.worker_stats)
      process_batch(batch_results, baseline_result, state)
    end
    all_worker_stats
  end

  def log_worker_diagnostics(worker_stats)
    return unless @diagnostics

    @diagnostics.log_worker_stats(worker_stats)
  end

  def build_result(state, worker_stats)
    Evilution::Runner::MutationExecutor::ExecutionResult.new(
      results: state[:results], truncated: state[:truncated], worker_stats: worker_stats
    )
  end

  def run_batch(batch, pool, integration)
    partition = @cache.partition(batch, packer: @packer)
    worker_results = run_uncached(batch, partition.uncached_indices, pool, integration)
    compact_results = merge(batch, partition.uncached_indices, partition.cached_results, worker_results)
    batch_results = rebuild_results(batch, compact_results)
    cache_results(batch_results, partition.uncached_indices)
    release_sources(batch, batch_results)
    batch_results
  end

  # Sources are dropped as soon as a mutation has been judged, to keep a long
  # run's memory flat. A mutation the workers could not judge because of
  # infrastructure contention is re-run serially once the pool is done
  # (InfraRetry), which needs its sources, so it keeps them until then. The
  # neutralisation pipeline has not run yet here, so the crash is still a kill.
  def release_sources(batch, batch_results)
    batch.each_with_index do |mutation, index|
      result = batch_results[index]
      next if result && infra_crash?(result)

      mutation.strip_sources!
    end
  end

  def infra_crash?(result)
    Evilution::InfraCrash.class_name?(result.error_class)
  end

  def rebuild_results(batch, compact_results)
    batch.zip(compact_results).map { |m, h| @packer.rebuild(m, h) }
  end

  def cache_results(batch_results, uncached_indices)
    uncached_indices.each { |i| @cache.store(batch_results[i].mutation, batch_results[i]) }
  end

  def run_uncached(batch, uncached_indices, pool, integration)
    return [] if uncached_indices.empty?

    uncached = uncached_indices.map { |i| batch[i] }
    dispatched_at = monotonic_now
    worker_results = pool.map(uncached) { |mutation| run_in_worker(mutation, integration, dispatched_at) }
    worker_results.map { |r| unpack_unfinished(r) }
  end

  # Runs in the worker. CLOCK_MONOTONIC is system-wide, so the parent's reading
  # at dispatch and the worker's here are on the same clock.
  def run_in_worker(mutation, integration, dispatched_at)
    queue_wait = monotonic_now - dispatched_at
    test_command = ->(m) { integration.call(m) }
    result = @isolator.call(mutation: mutation, test_command: test_command, timeout: @config.timeout)
    @packer.compact(result).merge(queue_wait: queue_wait)
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
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

  def merge(batch, uncached_indices, cached_results, worker_results)
    result_map = cached_results.dup
    uncached_indices.each_with_index { |batch_idx, worker_idx| result_map[batch_idx] = worker_results[worker_idx] }
    batch.each_index.map { |i| result_map[i] }
  end

  def process_batch(batch_results, baseline_result, state)
    batch_results.each do |result|
      result = @pipeline.call(result, baseline_result: baseline_result)
      state[:results] << result
      state[:completed] += 1
      if @notifier.notify(result, state[:completed]) == :truncate
        state[:truncated] = true
        break
      end
    end

    @diagnostics.log_memory("after batch", "#{state[:completed]} complete") if @diagnostics
  end
end
