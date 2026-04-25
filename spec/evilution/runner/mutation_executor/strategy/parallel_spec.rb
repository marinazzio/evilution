# frozen_string_literal: true

require "evilution/config"
require "evilution/mutation"
require "evilution/result/mutation_result"
require "evilution/runner/diagnostics"
require "evilution/runner/mutation_executor/result_cache"
require "evilution/runner/mutation_executor/result_packer"
require "evilution/runner/mutation_executor/result_notifier"
require "evilution/runner/mutation_executor/neutralization_pipeline"
require "evilution/runner/mutation_executor/strategy/parallel"

RSpec.describe Evilution::Runner::MutationExecutor::Strategy::Parallel do
  let(:cfg) do
    Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, jobs: 2, timeout: 30)
  end

  def mutation(id)
    instance_double(Evilution::Mutation, file_path: "lib/foo.rb", to_s: id, unparseable?: false, strip_sources!: nil)
  end

  def killed(mut)
    Evilution::Result::MutationResult.new(mutation: mut, status: :killed, duration: 0.1, killing_test: "t", test_command: "c")
  end

  def diagnostics
    diags = Evilution::Runner::Diagnostics.new(cfg)
    allow(diags).to receive(:log_memory)
    allow(diags).to receive(:log_worker_stats)
    allow(diags).to receive(:aggregate_worker_stats).and_return({})
    diags
  end

  def notifier(diags = diagnostics)
    Evilution::Runner::MutationExecutor::ResultNotifier.new(cfg, diagnostics: diags, on_result: nil)
  end

  it "calls isolator inside the pool for uncached mutations and rebuilds via packer" do
    m1 = mutation("m1")
    m2 = mutation("m2")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)

    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(m1), killed(m2))

    packer = Evilution::Runner::MutationExecutor::ResultPacker.new
    pool = double(:pool)
    allow(pool).to receive(:worker_stats).and_return([])
    allow(pool).to receive(:map) { |uncached, &block| uncached.map(&block) }

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: packer,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier,
      pool_factory: -> { pool },
      config: cfg
    )

    results, truncated = strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(results.map(&:status)).to eq(%i[killed killed])
    expect(truncated).to be false
  end

  it "uses cached results in place of pool execution and preserves batch order" do
    m1 = mutation("m1")
    m2 = mutation("m2")
    backend = instance_double("Cache")
    allow(backend).to receive(:fetch).with(m1).and_return(nil)
    allow(backend).to receive(:fetch).with(m2).and_return(status: :killed, duration: 0.5, killing_test: "k", test_command: "c")
    allow(backend).to receive(:store)

    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(m1))
    pool = double(:pool, worker_stats: [])
    allow(pool).to receive(:map) { |uncached, &block| uncached.map(&block) }

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier,
      pool_factory: -> { pool },
      config: cfg
    )

    results, = strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(results[0].status).to eq(:killed)
    expect(results[0].duration).to eq(0.1)
    expect(results[1].status).to eq(:killed)
    expect(results[1].duration).to eq(0.5)
  end

  it "stops processing further batches when notifier signals :truncate" do
    cfg_ff = Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, jobs: 1, fail_fast: 1)
    m1 = mutation("m1")
    m2 = mutation("m2")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(
      Evilution::Result::MutationResult.new(mutation: m1, status: :survived, duration: 0.01)
    )
    pool = double(:pool, worker_stats: [])
    allow(pool).to receive(:map) { |uncached, &block| uncached.map(&block) }
    diags = Evilution::Runner::Diagnostics.new(cfg_ff)
    allow(diags).to receive(:log_memory)
    allow(diags).to receive(:log_worker_stats)
    allow(diags).to receive(:aggregate_worker_stats).and_return({})

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: Evilution::Runner::MutationExecutor::ResultNotifier.new(cfg_ff, diagnostics: diags, on_result: nil),
      pool_factory: -> { pool },
      config: cfg_ff
    )

    results, truncated = strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(results.length).to eq(1)
    expect(truncated).to be true
    expect(isolator).to have_received(:call).once
  end

  it "calls strip_sources! on every mutation in batch and logs memory after batch" do
    m1 = mutation("m1")
    expect(m1).to receive(:strip_sources!)

    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(m1))
    pool = double(:pool, worker_stats: [])
    allow(pool).to receive(:map) { |uncached, &block| uncached.map(&block) }
    diags = diagnostics
    expect(diags).to receive(:log_memory).with("after batch", an_instance_of(String))

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier(diags),
      pool_factory: -> { pool },
      config: cfg,
      diagnostics: diags
    )

    strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" })
  end
end
