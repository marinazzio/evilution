# frozen_string_literal: true

require_relative "../parallel/pool"
require_relative "mutation_executor/result_cache"
require_relative "mutation_executor/result_packer"
require_relative "mutation_executor/result_notifier"
require_relative "mutation_executor/mutation_runner"
require_relative "mutation_executor/neutralization_pipeline"
require_relative "mutation_executor/neutralizer/infra_error"
require_relative "mutation_executor/neutralizer/baseline_failed"
require_relative "mutation_executor/strategy/sequential"
require_relative "mutation_executor/strategy/parallel"

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass

class Evilution::Runner::MutationExecutor
  InfraError = Neutralizer::InfraError
  BaselineFailed = Neutralizer::BaselineFailed
  Sequential = Strategy::Sequential
  Parallel = Strategy::Parallel

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
    ResultNotifier.new(@config, hooks: @hooks, diagnostics: @diagnostics, on_result: @on_result)
  end

  def build_pipeline(spec_resolver)
    NeutralizationPipeline.new(
      [
        InfraError.new,
        BaselineFailed.new(
          config: @config,
          spec_resolver: spec_resolver || ->(_f) {},
          fallback_dir: @baseline_runner.neutralization_fallback_dir
        )
      ]
    )
  end

  def build_sequential(notifier, pipeline)
    Sequential.new(
      runner: MutationRunner.new(config: @config, cache: @cache, isolator: @isolator),
      pipeline: pipeline,
      notifier: notifier
    )
  end

  def build_parallel(notifier, pipeline)
    Parallel.new(
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
