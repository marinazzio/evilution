# frozen_string_literal: true

require_relative "../parallel/pool"
require_relative "../reporter/progress_bar"
require_relative "../result/mutation_result"

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass

class Evilution::Runner::MutationExecutor
  def initialize(config, isolator:, baseline_runner:, cache:, hooks:, diagnostics:, on_result: nil)
    @config = config
    @isolator = isolator
    @baseline_runner = baseline_runner
    @cache = cache
    @hooks = hooks
    @diagnostics = diagnostics
    @on_result = on_result
  end

  def call(mutations, baseline_result = nil)
    @progress_bar = build_progress_bar(mutations.length)
    result = if config.jobs > 1
               run_parallel(mutations, baseline_result)
             else
               run_sequential(mutations, baseline_result)
             end
    @progress_bar&.finish
    result
  end

  private

  attr_reader :config, :isolator, :baseline_runner, :cache, :hooks, :diagnostics, :on_result

  def run_sequential(mutations, baseline_result)
    integration = baseline_runner.build_integration
    spec_resolver = baseline_result&.failed? ? baseline_runner.neutralization_resolver : nil
    results = []
    survived_count = 0
    truncated = false

    mutations.each_with_index do |mutation, index|
      result = execute_or_fetch(mutation) do
        test_command = ->(m) { integration.call(m) }
        isolator.call(mutation: mutation, test_command: test_command, timeout: config.timeout)
      end
      mutation.strip_sources!
      result = neutralize_if_baseline_failed(result, baseline_result, spec_resolver)
      results << result
      survived_count += 1 if result.survived?
      notify_result(result, index + 1)

      if config.fail_fast? && survived_count >= config.fail_fast
        truncated = true
        break
      end
    end

    [results, truncated]
  end

  def run_parallel(mutations, baseline_result)
    integration = baseline_runner.build_integration
    pool = build_pool
    spec_resolver = baseline_result&.failed? ? baseline_runner.neutralization_resolver : nil
    state = { results: [], survived_count: 0, truncated: false, completed: 0 }
    all_worker_stats = []

    mutations.each_slice(config.jobs) do |batch|
      break if state[:truncated]

      batch_results = run_parallel_batch(batch, pool, isolator, integration)
      all_worker_stats.concat(pool.worker_stats)
      process_batch(batch_results, baseline_result, spec_resolver, state)
    end

    diagnostics.log_worker_stats(diagnostics.aggregate_worker_stats(all_worker_stats))
    [state[:results], state[:truncated]]
  end

  def build_pool
    Evilution::Parallel::Pool.new(
      size: config.jobs,
      hooks: hooks,
      item_timeout: config.timeout ? config.timeout * 2 : nil
    )
  end

  def run_parallel_batch(batch, pool, worker_isolator, integration)
    uncached_indices, cached_results = partition_cached(batch)
    worker_results = run_uncached_workers(batch, uncached_indices, pool, worker_isolator, integration)
    compact_results = merge_parallel_results(batch, uncached_indices, cached_results, worker_results)
    batch.each(&:strip_sources!)
    batch_results = rebuild_results(batch, compact_results)
    batch_results.each { |r| store_cached_result(r.mutation, r) }
    batch_results
  end

  def run_uncached_workers(batch, uncached_indices, pool, worker_isolator, integration)
    return [] if uncached_indices.empty?

    uncached = uncached_indices.map { |i| batch[i] }
    pool.map(uncached) do |mutation|
      test_command = ->(m) { integration.call(m) }
      result = worker_isolator.call(mutation: mutation, test_command: test_command, timeout: config.timeout)
      compact_result(result)
    end
  end

  def process_batch(batch_results, baseline_result, spec_resolver, state)
    batch_results.each do |result|
      result = neutralize_if_baseline_failed(result, baseline_result, spec_resolver)
      state[:results] << result
      state[:survived_count] += 1 if result.survived?
      state[:completed] += 1
      notify_result(result, state[:completed])
    end

    diagnostics.log_memory("after batch", "#{state[:completed]} complete")
    state[:truncated] = true if should_truncate?(state[:survived_count])
  end

  def neutralize_if_baseline_failed(result, baseline_result, spec_resolver)
    return result unless result.survived? && baseline_result && baseline_result.failed?

    if config.spec_files.any?
      neutralize = true
    else
      spec_file = spec_resolver.call(result.mutation.file_path) || baseline_runner.neutralization_fallback_dir
      neutralize = baseline_result.failed_spec_files.include?(spec_file)
    end
    return result unless neutralize

    Evilution::Result::MutationResult.new(
      mutation: result.mutation,
      status: :neutral,
      duration: result.duration,
      test_command: result.test_command,
      child_rss_kb: result.child_rss_kb,
      memory_delta_kb: result.memory_delta_kb,
      parent_rss_kb: result.parent_rss_kb,
      error_message: result.error_message,
      error_class: result.error_class,
      error_backtrace: result.error_backtrace
    )
  end

  def compact_result(result)
    {
      status: result.status,
      duration: result.duration,
      killing_test: result.killing_test,
      test_command: result.test_command,
      child_rss_kb: result.child_rss_kb,
      memory_delta_kb: result.memory_delta_kb,
      parent_rss_kb: result.parent_rss_kb,
      error_message: result.error_message,
      error_class: result.error_class,
      error_backtrace: result.error_backtrace
    }
  end

  def rebuild_results(batch, compact_results)
    batch.zip(compact_results).map do |mutation, data|
      Evilution::Result::MutationResult.new(
        mutation: mutation,
        status: data[:status],
        duration: data[:duration],
        killing_test: data[:killing_test],
        test_command: data[:test_command],
        child_rss_kb: data[:child_rss_kb],
        memory_delta_kb: data[:memory_delta_kb],
        parent_rss_kb: data[:parent_rss_kb],
        error_message: data[:error_message],
        error_class: data[:error_class],
        error_backtrace: data[:error_backtrace]
      )
    end
  end

  def should_truncate?(survived_count)
    config.fail_fast? && survived_count >= config.fail_fast
  end

  def partition_cached(batch)
    uncached_indices = []
    cached_results = {}

    batch.each_with_index do |mutation, i|
      cached = fetch_cached_result(mutation)
      if cached
        cached_results[i] = compact_result(cached)
      else
        uncached_indices << i
      end
    end

    [uncached_indices, cached_results]
  end

  def merge_parallel_results(batch, uncached_indices, cached_results, worker_results)
    result_map = cached_results.dup
    uncached_indices.each_with_index { |batch_idx, worker_idx| result_map[batch_idx] = worker_results[worker_idx] }
    batch.each_index.map { |i| result_map[i] }
  end

  def execute_or_fetch(mutation)
    cached = fetch_cached_result(mutation)
    return cached if cached

    result = yield
    store_cached_result(mutation, result)
    result
  end

  def fetch_cached_result(mutation)
    return nil unless cache

    data = cache.fetch(mutation)
    return nil unless data
    return nil unless %i[killed timeout].include?(data[:status])

    Evilution::Result::MutationResult.new(
      mutation: mutation,
      status: data[:status],
      duration: data[:duration],
      killing_test: data[:killing_test],
      test_command: data[:test_command]
    )
  end

  def store_cached_result(mutation, result)
    return unless cache
    return unless result.killed? || result.timeout?

    cache.store(mutation,
                status: result.status,
                duration: result.duration,
                killing_test: result.killing_test,
                test_command: result.test_command)
  end

  def notify_result(result, index)
    on_result&.call(result)
    @progress_bar&.tick(status: result.status)
    diagnostics.log_progress(index, result.status)
    diagnostics.log_mutation_diagnostics(result)
  end

  def build_progress_bar(total)
    return nil if !config.progress? || config.quiet || config.verbose || !config.text? || !$stderr.tty?

    Evilution::Reporter::ProgressBar.new(total: total, output: $stderr)
  end
end
