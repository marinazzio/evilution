# frozen_string_literal: true

require_relative "../strategy"

class Evilution::Runner::MutationExecutor::Strategy::Parallel
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
    all_worker_stats = run_batches(mutations, pool, baseline_result, integration, state)

    log_worker_diagnostics(all_worker_stats)
    @notifier.finish
    build_result(state)
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

  def log_worker_diagnostics(all_worker_stats)
    return unless @diagnostics

    @diagnostics.log_worker_stats(@diagnostics.aggregate_worker_stats(all_worker_stats))
  end

  def build_result(state)
    Evilution::Runner::MutationExecutor::ExecutionResult.new(results: state[:results], truncated: state[:truncated])
  end

  def run_batch(batch, pool, integration)
    partition = @cache.partition(batch, packer: @packer)
    worker_results = run_uncached(batch, partition.uncached_indices, pool, integration)
    compact_results = merge(batch, partition.uncached_indices, partition.cached_results, worker_results)
    batch_results = rebuild_results(batch, compact_results)
    cache_results(batch_results, partition.uncached_indices)
    batch.each(&:strip_sources!)
    batch_results
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
    pool.map(uncached) do |mutation|
      test_command = ->(m) { integration.call(m) }
      result = @isolator.call(mutation: mutation, test_command: test_command, timeout: @config.timeout)
      @packer.compact(result)
    end
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
