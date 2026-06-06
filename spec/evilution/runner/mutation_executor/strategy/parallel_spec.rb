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
require "evilution/parallel/work_queue"

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

    execution = strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(execution.results.map(&:status)).to eq(%i[killed killed])
    expect(execution.truncated).to be false
  end

  it "translates a TIMED_OUT pool sentinel into a :timeout result" do
    m1 = mutation("m1")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    pool = double(:pool, worker_stats: [])
    allow(pool).to receive(:map).and_return([Evilution::Parallel::WorkQueue::TIMED_OUT])

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier,
      pool_factory: -> { pool },
      config: cfg
    )

    execution = strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" })

    result = execution.results.first
    expect(result.status).to eq(:timeout)
    expect(result.mutation).to eq(m1)
    # Duration reflects the item_timeout the stuck worker exhausted (config
    # timeout 30 * 2), not a misleading 0.0 that would be cached/reported.
    expect(result.duration).to eq(60.0)
  end

  it "translates a DIED pool sentinel into an :error result" do
    m1 = mutation("m1")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    pool = double(:pool, worker_stats: [])
    allow(pool).to receive(:map).and_return([Evilution::Parallel::WorkQueue::DIED])

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier,
      pool_factory: -> { pool },
      config: cfg
    )

    execution = strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" })

    result = execution.results.first
    expect(result.status).to eq(:error)
    expect(result.error_message).to match(/worker process exited unexpectedly/)
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

    execution = strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })
    results = execution.results

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

    execution = strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(execution.results.length).to eq(1)
    expect(execution.truncated).to be true
    expect(isolator).to have_received(:call).once
  end

  it "breaks out of the current batch mid-iteration when notifier signals :truncate" do
    cfg_ff = Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, jobs: 2, fail_fast: 1)
    m1 = mutation("m1")
    m2 = mutation("m2")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    survived = lambda do |mut|
      Evilution::Result::MutationResult.new(mutation: mut, status: :survived, duration: 0.01)
    end
    allow(isolator).to receive(:call).and_return(survived.call(m1), survived.call(m2))
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

    execution = strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(execution.results.length).to eq(1)
    expect(execution.truncated).to be true
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

  it "starts the notifier with the mutation count and finishes it" do
    m1 = mutation("m1")
    m2 = mutation("m2")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(m1), killed(m2))
    pool = double(:pool, worker_stats: [])
    allow(pool).to receive(:map) { |uncached, &block| uncached.map(&block) }

    notifier_spy = instance_spy(Evilution::Runner::MutationExecutor::ResultNotifier)
    allow(notifier_spy).to receive(:notify).and_return(:continue)

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier_spy,
      pool_factory: -> { pool },
      config: cfg
    )

    strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(notifier_spy).to have_received(:start).with(2)
    expect(notifier_spy).to have_received(:finish)
  end

  it "notifies the notifier once per result with an incrementing completed count" do
    m1 = mutation("m1")
    m2 = mutation("m2")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(m1), killed(m2))
    pool = double(:pool, worker_stats: [])
    allow(pool).to receive(:map) { |uncached, &block| uncached.map(&block) }

    notifier_spy = instance_spy(Evilution::Runner::MutationExecutor::ResultNotifier)
    allow(notifier_spy).to receive(:notify).and_return(:continue)

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier_spy,
      pool_factory: -> { pool },
      config: cfg
    )

    strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(notifier_spy).to have_received(:notify).with(an_instance_of(Evilution::Result::MutationResult), 1).ordered
    expect(notifier_spy).to have_received(:notify).with(an_instance_of(Evilution::Result::MutationResult), 2).ordered
  end

  it "aggregates worker stats from every batch and logs them via diagnostics" do
    cfg_j1 = Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, jobs: 1, timeout: 30)
    m1 = mutation("m1")
    m2 = mutation("m2")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(m1), killed(m2))
    stats_batch1 = [:s1]
    stats_batch2 = [:s2]
    pool = double(:pool)
    allow(pool).to receive(:worker_stats).and_return(stats_batch1, stats_batch2)
    allow(pool).to receive(:map) { |uncached, &block| uncached.map(&block) }

    diags = Evilution::Runner::Diagnostics.new(cfg_j1)
    allow(diags).to receive(:log_memory)
    allow(diags).to receive(:aggregate_worker_stats).and_return(:aggregated)
    allow(diags).to receive(:log_worker_stats)

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier(diags),
      pool_factory: -> { pool },
      config: cfg_j1,
      diagnostics: diags
    )

    strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(diags).to have_received(:aggregate_worker_stats).with(%i[s1 s2])
    expect(diags).to have_received(:log_worker_stats).with(:aggregated)
  end

  it "does not call worker diagnostics when no diagnostics object is provided" do
    m1 = mutation("m1")
    backend = instance_double("Cache", fetch: nil)
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
      config: cfg,
      diagnostics: nil
    )

    expect { strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" }) }.not_to raise_error
  end

  it "applies the neutralization pipeline to each result" do
    m1 = mutation("m1")
    raw = killed(m1)
    transformed = Evilution::Result::MutationResult.new(mutation: m1, status: :survived, duration: 0.2)
    pipeline = instance_double(Evilution::Runner::MutationExecutor::NeutralizationPipeline)
    allow(pipeline).to(
      receive(:call)
        .with(an_instance_of(Evilution::Result::MutationResult), baseline_result: nil)
        .and_return(transformed)
    )

    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(raw)
    pool = double(:pool, worker_stats: [])
    allow(pool).to receive(:map) { |uncached, &block| uncached.map(&block) }

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: pipeline,
      notifier: notifier,
      pool_factory: -> { pool },
      config: cfg
    )

    execution = strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(execution.results.map(&:status)).to eq(%i[survived])
  end

  it "passes the integration call result as the test command to the isolator" do
    m1 = mutation("m1")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    captured_command = nil
    allow(isolator).to receive(:call) do |mutation:, test_command:, timeout: nil|
      _ = timeout
      captured_command = test_command.call(mutation)
      killed(m1)
    end
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

    strategy.call([m1], baseline_result: nil, integration: ->(m) { "test-cmd-for-#{m}" })

    expect(captured_command).to eq("test-cmd-for-m1")
  end

  it "passes individual batch mutations (not indices or the whole batch) to the pool" do
    m1 = mutation("m1")
    m2 = mutation("m2")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    isolated = []
    allow(isolator).to receive(:call) do |mutation:, test_command: nil, timeout: nil|
      _ = [test_command, timeout]
      isolated << mutation
      killed(mutation)
    end
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

    strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(isolated).to eq([m1, m2])
  end

  it "does not invoke the pool when every mutation in the batch is cached" do
    m1 = mutation("m1")
    backend = instance_double("Cache")
    allow(backend).to(
      receive(:fetch)
        .with(m1)
        .and_return(status: :killed, duration: 0.5, killing_test: "k", test_command: "c")
    )
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    pool = double(:pool, worker_stats: [])
    allow(pool).to receive(:map)

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier,
      pool_factory: -> { pool },
      config: cfg
    )

    execution = strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(pool).not_to have_received(:map)
    expect(execution.results.map(&:status)).to eq(%i[killed])
  end

  it "logs the completed count (not the whole state hash) in the after-batch memory log" do
    m1 = mutation("m1")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(m1))
    pool = double(:pool, worker_stats: [])
    allow(pool).to receive(:map) { |uncached, &block| uncached.map(&block) }
    diags = diagnostics
    expect(diags).to receive(:log_memory).with("after batch", "1 complete")

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

  it "stores cache entries before stripping sources so backend sees non-nil original_source" do
    m1 = instance_double(
      Evilution::Mutation,
      file_path: "lib/foo.rb",
      to_s: "m1",
      unparseable?: false,
      original_source: "x = 1\n"
    )
    call_order = []
    allow(m1).to receive(:strip_sources!) do
      call_order << :strip
      allow(m1).to receive(:original_source).and_return(nil)
    end

    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store) do |mutation, _result|
      call_order << :store
      expect(mutation.original_source).not_to be_nil
    end

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

    strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(call_order).to eq(%i[store strip])
  end
end
