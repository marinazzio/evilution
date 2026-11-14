# frozen_string_literal: true

require_relative "../runner"

class Evilution::Runner::MutationExecutor
  ExecutionResult = Data.define(:results, :truncated, :infra_retried, :worker_stats) do
    def initialize(results:, truncated:, infra_retried: 0, worker_stats: [])
      super
    end
  end

  autoload :ResultCache, File.expand_path("mutation_executor/result_cache", __dir__)
  autoload :ResultPacker, File.expand_path("mutation_executor/result_packer", __dir__)
  autoload :ResultNotifier, File.expand_path("mutation_executor/result_notifier", __dir__)
  autoload :MutationRunner, File.expand_path("mutation_executor/mutation_runner", __dir__)
  autoload :NeutralizationPipeline, File.expand_path("mutation_executor/neutralization_pipeline", __dir__)
  autoload :InfraRetry, File.expand_path("mutation_executor/infra_retry", __dir__)
  autoload :Strategy, File.expand_path("mutation_executor/strategy", __dir__)
  autoload :Neutralizer, File.expand_path("mutation_executor/neutralizer", __dir__)
  autoload :TimeoutPolicy, File.expand_path("mutation_executor/timeout_policy", __dir__)
  autoload :RunlessVerdict, File.expand_path("mutation_executor/runless_verdict", __dir__)
  autoload :KillHistory, File.expand_path("mutation_executor/kill_history", __dir__)
  autoload :ProbeFirst, File.expand_path("mutation_executor/probe_first", __dir__)
  autoload :ProbeFirstRun, File.expand_path("mutation_executor/probe_first_run", __dir__)

  def initialize(config, isolator:, baseline_runner:, cache:, hooks:, diagnostics:, on_result: nil)
    @config = config
    @isolator = isolator
    @baseline_runner = baseline_runner
    @cache = ResultCache.new(cache)
    @packer = ResultPacker.new
    @hooks = hooks
    @diagnostics = diagnostics
    @on_result = on_result
  end

  def call(mutations, baseline_result = nil)
    integration = @baseline_runner.build_integration(baseline_result)
    warm(integration, mutations)
    spec_resolver = baseline_failed?(baseline_result) ? @baseline_runner.neutralization_resolver : nil
    notifier = build_notifier
    pipeline = build_pipeline(spec_resolver)
    prepare_run(baseline_result, integration)
    return run_batch(notifier, pipeline, mutations, baseline_result, integration) unless @config.probe_first?

    ProbeFirstRun.new(probe: @probe, notifier: notifier).call(mutations) do |batch, batch_notifier|
      run_batch(batch_notifier, pipeline, batch, baseline_result, integration)
    end
  ensure
    # The cache holds the verdicts stored since it last wrote a file; a run
    # that stops early keeps the ones it reached.
    @cache.flush
  end

  private

  # What the run decides once, before any mutation: each one's time limit,
  # the verdicts given without a run, and the kills remembered along the way.
  def prepare_run(baseline_result, integration)
    @timeout_policy = TimeoutPolicy.build(@config, baseline_result)
    @probe = @config.probe_first? ? ProbeFirst.new : ProbeFirst::NONE
    @runless = RunlessVerdict.new(coverage: uncovered_lines(integration), probe: @probe)
    @kill_history = KillHistory.new
  end

  # Here, before the first mutation child or pool worker is forked, so every
  # one of them inherits the filled caches rather than parsing the same source
  # and spec files, or walking the same heap, for itself and losing the
  # result when it exits. An integration is any callable; one without such
  # caches has no hook.
  def warm(integration, mutations)
    integration.warm_targeting(mutations) if integration.respond_to?(:warm_targeting)
    integration.warm_loading if integration.respond_to?(:warm_loading)
  end

  def run_batch(notifier, pipeline, mutations, baseline_result, integration)
    return sequential_run(notifier, pipeline, mutations, baseline_result, integration) if @config.jobs <= 1

    parallel_run(notifier, pipeline, mutations, baseline_result, integration)
  end

  def sequential_run(notifier, pipeline, mutations, baseline_result, integration)
    build_sequential(notifier, pipeline)
      .call(mutations, baseline_result: baseline_result, integration: integration)
  end

  # Infrastructure contention only exists while the pool is running, so the
  # mutations it left without a verdict are re-run once it is done. Without
  # this the neutral bucket swings with --jobs on identical input
  # (EV-j0bv / GH #1607).
  def parallel_run(notifier, pipeline, mutations, baseline_result, integration)
    execution = build_parallel(notifier, pipeline)
                .call(mutations, baseline_result: baseline_result, integration: integration)
    retry_pass = InfraRetry.new(runner: build_mutation_runner, pipeline: pipeline)
    results = retry_pass.call(execution.results, baseline_result: baseline_result, integration: integration)

    ExecutionResult.new(results: results, truncated: execution.truncated,
                        infra_retried: retry_pass.retried_count, worker_stats: execution.worker_stats)
  end

  # What tells the mutations no test executes, when the run skips them: the
  # integration, which only knows with a coverage map behind it.
  def uncovered_lines(integration)
    return nil unless @config.skip_uncovered? && integration.respond_to?(:uncovered?)

    integration
  end

  def build_mutation_runner
    MutationRunner.new(cache: @cache, isolator: @isolator, timeout_policy: @timeout_policy, runless: @runless,
                       kill_history: @kill_history)
  end

  def baseline_failed?(baseline_result)
    baseline_result && baseline_result.failed?
  end

  def build_notifier
    ResultNotifier.new(@config, diagnostics: @diagnostics, on_result: @on_result)
  end

  def build_pipeline(spec_resolver)
    NeutralizationPipeline.new(
      [
        Neutralizer::InfraError.new,
        Neutralizer::BaselineFailed.new(
          config: @config,
          spec_resolver: spec_resolver || ->(_f) {},
          fallback_dir: @baseline_runner.neutralization_fallback_dir
        )
      ]
    )
  end

  def build_sequential(notifier, pipeline)
    Strategy::Sequential.new(
      runner: build_mutation_runner,
      pipeline: pipeline,
      notifier: notifier
    )
  end

  def build_parallel(notifier, pipeline)
    Strategy::Parallel.new(
      cache: @cache,
      isolator: @isolator,
      packer: @packer,
      pipeline: pipeline,
      notifier: notifier,
      pool_factory: ->(item_timeout) { build_pool(item_timeout) },
      diagnostics: @diagnostics,
      config: @config,
      timeout_policy: @timeout_policy,
      runless: @runless,
      kill_history: @kill_history
    )
  end

  def build_pool(item_timeout)
    Evilution::Parallel::Pool.new(size: @config.jobs, hooks: @hooks, item_timeout: item_timeout)
  end
end
