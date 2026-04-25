# frozen_string_literal: true

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass
class Evilution::Runner::MutationExecutor; end unless defined?(Evilution::Runner::MutationExecutor) # rubocop:disable Lint/EmptyClass
module Evilution::Runner::MutationExecutor::Strategy; end unless defined?(Evilution::Runner::MutationExecutor::Strategy)

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
    all_worker_stats = []

    mutations.each_slice(@config.jobs) do |batch|
      break if state[:truncated]

      batch_results = run_batch(batch, pool, integration)
      all_worker_stats.concat(pool.worker_stats)
      process_batch(batch_results, baseline_result, state)
    end

    @diagnostics.log_worker_stats(@diagnostics.aggregate_worker_stats(all_worker_stats)) if @diagnostics
    @notifier.finish
    [state[:results], state[:truncated]]
  end

  private

  def run_batch(batch, pool, integration)
    uncached_indices, cached_results = @cache.partition(batch, packer: @packer)
    worker_results = run_uncached(batch, uncached_indices, pool, integration)
    compact_results = merge(batch, uncached_indices, cached_results, worker_results)
    batch.each(&:strip_sources!)
    batch_results = batch.zip(compact_results).map { |m, h| @packer.rebuild(m, h) }
    batch_results.each { |r| @cache.store(r.mutation, r) }
    batch_results
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
