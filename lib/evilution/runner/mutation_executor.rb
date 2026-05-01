# frozen_string_literal: true

require_relative "../runner"

class Evilution::Runner::MutationExecutor
  autoload :ResultCache, File.expand_path("mutation_executor/result_cache", __dir__)
  autoload :ResultPacker, File.expand_path("mutation_executor/result_packer", __dir__)
  autoload :ResultNotifier, File.expand_path("mutation_executor/result_notifier", __dir__)
  autoload :MutationRunner, File.expand_path("mutation_executor/mutation_runner", __dir__)
  autoload :NeutralizationPipeline, File.expand_path("mutation_executor/neutralization_pipeline", __dir__)
  autoload :Strategy, File.expand_path("mutation_executor/strategy", __dir__)
  autoload :Neutralizer, File.expand_path("mutation_executor/neutralizer", __dir__)

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
    integration = @baseline_runner.build_integration
    spec_resolver = baseline_failed?(baseline_result) ? @baseline_runner.neutralization_resolver : nil
    notifier = build_notifier
    pipeline = build_pipeline(spec_resolver)
    strategy = @config.jobs > 1 ? build_parallel(notifier, pipeline) : build_sequential(notifier, pipeline)

    strategy.call(mutations, baseline_result: baseline_result, integration: integration)
  end

  private

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
      runner: MutationRunner.new(config: @config, cache: @cache, isolator: @isolator),
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
      pool_factory: -> { build_pool },
      diagnostics: @diagnostics,
      config: @config
    )
  end

  def build_pool
    Evilution::Parallel::Pool.new(
      size: @config.jobs,
      hooks: @hooks,
      item_timeout: @config.timeout ? @config.timeout * 2 : nil
    )
  end
end
