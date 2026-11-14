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
require "evilution/runner/mutation_executor/timeout_policy"
require "evilution/parallel/work_queue"
require_relative "../../../../support/streaming_pool"

RSpec.describe Evilution::Runner::MutationExecutor::Strategy::Parallel do
  let(:cfg) do
    Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, jobs: 2, timeout: 30)
  end

  def mutation(id)
    instance_double(Evilution::Mutation, file_path: "lib/foo.rb", to_s: id, unparseable?: false, strip_sources!: nil)
  end

  def infra_crash(mut)
    Evilution::Result::MutationResult.new(
      mutation: mut, status: :killed, duration: 0.1, test_command: "c",
      error: Evilution::Result::ErrorInfo.new(klass: "Timeout::Error", message: "execution expired")
    )
  end

  def killed(mut)
    Evilution::Result::MutationResult.new(mutation: mut, status: :killed, duration: 0.1, killing_test: "t", test_command: "c")
  end

  def diagnostics
    diags = Evilution::Runner::Diagnostics.new(cfg)
    allow(diags).to receive(:log_memory)
    allow(diags).to receive(:log_worker_stats)
    diags
  end

  def fake_pool(**)
    StreamingPool.new(**)
  end

  def notifier(diags = diagnostics)
    Evilution::Runner::MutationExecutor::ResultNotifier.new(cfg, diagnostics: diags, on_result: nil)
  end

  describe "timings" do
    def strategy_with(pool, isolator)
      backend = instance_double("Cache", fetch: nil)
      allow(backend).to receive(:store)
      described_class.new(
        cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
        isolator: isolator,
        packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
        pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
        notifier: notifier,
        pool_factory: ->(_item_timeout) { pool },
        config: cfg
      )
    end

    it "records the wait the worker measured between the item being sent and picked up" do
      m1 = mutation("m1")
      isolator = double(:isolator)
      allow(isolator).to receive(:call).and_return(killed(m1))

      execution = strategy_with(fake_pool(waited: 0.25), isolator)
                  .call([m1], baseline_result: nil, integration: ->(_) { "cmd" })

      expect(execution.results.first.timings.queue_wait).to eq(0.25)
    end

    it "records no wait when the worker measured none" do
      m1 = mutation("m1")
      isolator = double(:isolator)
      allow(isolator).to receive(:call).and_return(killed(m1))

      execution = strategy_with(fake_pool, isolator).call([m1], baseline_result: nil, integration: ->(_) { "cmd" })

      expect(execution.results.first.timings).to be_nil
    end

    it "returns one row per worker process, summing a pid reported twice" do
      stat = Evilution::Parallel::WorkQueue::WorkerStat
      isolator = double(:isolator)
      allow(isolator).to receive(:call) { |mutation:, **| killed(mutation) }
      pool = fake_pool(worker_stats: [stat.new(11, 1, 1.0, 2.0), stat.new(12, 1, 2.0, 2.0), stat.new(11, 1, 0.5, 1.0)])

      execution = strategy_with(pool, isolator)
                  .call([mutation("m1"), mutation("m2"), mutation("m3")], baseline_result: nil, integration: ->(_) { "cmd" })

      expect(execution.worker_stats.map(&:to_a)).to contain_exactly([11, 2, 1.5, 3.0], [12, 1, 2.0, 2.0])
    end
  end

  describe "streaming" do
    def strategy_for(pool, isolator, config: cfg, notifier: nil, backend: nil, timeout_policy: nil, pool_factory: nil)
      backend ||= instance_double("Cache", fetch: nil).tap { |b| allow(b).to receive(:store) }
      diags = Evilution::Runner::Diagnostics.new(config)
      allow(diags).to receive(:log_memory)
      described_class.new(
        cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
        isolator: isolator,
        packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
        pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
        notifier: notifier || Evilution::Runner::MutationExecutor::ResultNotifier.new(config, diagnostics: diags, on_result: nil),
        pool_factory: pool_factory || ->(_item_timeout) { pool },
        config: config,
        timeout_policy: timeout_policy
      )
    end

    def echo_isolator
      isolator = double(:isolator)
      allow(isolator).to receive(:call) { |mutation:, **| killed(mutation) }
      isolator
    end

    it "hands every uncached mutation to the pool in one run, whatever --jobs is" do
      pool = fake_pool
      mutations = Array.new(5) { |i| mutation("m#{i}") }

      strategy_for(pool, echo_isolator).call(mutations, baseline_result: nil, integration: ->(_) { "cmd" })

      expect(pool.map_calls).to eq(1)
    end

    it "lists results in mutation order when workers finish out of order" do
      mutations = Array.new(4) { |i| mutation("m#{i}") }

      execution = strategy_for(fake_pool(order: [2, 0, 3, 1]), echo_isolator)
                  .call(mutations, baseline_result: nil, integration: ->(_) { "cmd" })

      expect(execution.results.map(&:mutation)).to eq(mutations)
    end

    it "notifies in mutation order when workers finish out of order" do
      mutations = Array.new(3) { |i| mutation("m#{i}") }
      notifier_spy = instance_spy(Evilution::Runner::MutationExecutor::ResultNotifier)
      seen = []
      allow(notifier_spy).to receive(:notify) do |result, count|
        seen << [result.mutation.to_s, count]
        :continue
      end

      strategy_for(fake_pool(order: [2, 1, 0]), echo_isolator, notifier: notifier_spy)
        .call(mutations, baseline_result: nil, integration: ->(_) { "cmd" })

      expect(seen).to eq([["m0", 1], ["m1", 2], ["m2", 3]])
    end

    it "places cached results among the pool's in mutation order" do
      mutations = Array.new(3) { |i| mutation("m#{i}") }
      backend = instance_double("Cache")
      allow(backend).to receive(:store)
      allow(backend).to receive(:fetch) do |m|
        { status: :timeout, duration: 9.0 } if m.equal?(mutations[1])
      end

      execution = strategy_for(fake_pool(order: [1, 0]), echo_isolator, backend: backend)
                  .call(mutations, baseline_result: nil, integration: ->(_) { "cmd" })

      expect(execution.results.map(&:status)).to eq(%i[killed timeout killed])
      expect(backend).to have_received(:store).twice
    end

    it "stops the pool at the first survivor in mutation order under fail-fast" do
      cfg_ff = Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, jobs: 2, fail_fast: 1)
      mutations = Array.new(5) { |i| mutation("m#{i}") }
      isolator = double(:isolator)
      allow(isolator).to receive(:call) do |mutation:, **|
        if mutation.equal?(mutations[1])
          Evilution::Result::MutationResult.new(mutation: mutation, status: :survived, duration: 0.01)
        else
          killed(mutation)
        end
      end
      pool = fake_pool(order: [2, 1, 0, 3, 4])

      execution = strategy_for(pool, isolator, config: cfg_ff)
                  .call(mutations, baseline_result: nil, integration: ->(_) { "cmd" })

      expect(execution.results.map(&:mutation)).to eq(mutations.first(2))
      expect(execution.truncated).to be true
      expect(pool.stopped).to be true
    end

    it "runs each mutation under the configured timeout" do
      isolator = double(:isolator)
      allow(isolator).to receive(:call) { |mutation:, **| killed(mutation) }

      strategy_for(fake_pool, isolator).call([mutation("m1")], baseline_result: nil, integration: ->(_) { "cmd" })

      expect(isolator).to have_received(:call).with(hash_including(timeout: 30))
    end

    it "runs each mutation under the limit the timeout policy gives it" do
      m1 = mutation("m1")
      m2 = instance_double(Evilution::Mutation, file_path: "lib/bar.rb", to_s: "m2", unparseable?: false,
                                                strip_sources!: nil)
      isolator = double(:isolator)
      allow(isolator).to receive(:call) { |mutation:, **| killed(mutation) }
      policy = ->(mut) { mut.equal?(m1) ? 4.0 : 7.5 }
      def policy.item_timeout(_mutations) = 15.0

      strategy_for(fake_pool, isolator, timeout_policy: policy)
        .call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

      expect(isolator).to have_received(:call).with(hash_including(mutation: m1, timeout: 4.0))
      expect(isolator).to have_received(:call).with(hash_including(mutation: m2, timeout: 7.5))
    end

    it "builds the pool with the item timeout the policy gives for the mutations it runs" do
      m1 = mutation("m1")
      policy = Evilution::Runner::MutationExecutor::TimeoutPolicy::Fixed.new(12)
      given = nil
      factory = lambda do |item_timeout|
        given = item_timeout
        fake_pool
      end
      strategy = strategy_for(nil, echo_isolator, timeout_policy: policy, pool_factory: factory)

      strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" })

      expect(given).to eq(24)
    end

    it "records the limit a timed-out mutation ran under" do
      m1 = mutation("m1")
      isolator = double(:isolator)
      allow(isolator).to receive(:call) do |mutation:, **|
        Evilution::Result::MutationResult.new(mutation: mutation, status: :timeout, duration: 4.1)
      end
      policy = Evilution::Runner::MutationExecutor::TimeoutPolicy::Fixed.new(4)

      execution = strategy_for(fake_pool, isolator, timeout_policy: policy)
                  .call([m1], baseline_result: nil, integration: ->(_) { "cmd" })

      expect(execution.results.first.time_limit).to eq(4)
    end

    it "records no limit on a mutation that finished in time" do
      execution = strategy_for(fake_pool, echo_isolator)
                  .call([mutation("m1")], baseline_result: nil, integration: ->(_) { "cmd" })

      expect(execution.results.first.time_limit).to be_nil
    end

    it "hands the baseline to the neutralisation pipeline" do
      pipeline = instance_double(Evilution::Runner::MutationExecutor::NeutralizationPipeline)
      allow(pipeline).to receive(:call) { |result, **| result }
      backend = instance_double("Cache", fetch: nil).tap { |b| allow(b).to receive(:store) }
      strategy = described_class.new(
        cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend), isolator: echo_isolator,
        packer: Evilution::Runner::MutationExecutor::ResultPacker.new, pipeline: pipeline,
        notifier: instance_spy(Evilution::Runner::MutationExecutor::ResultNotifier, notify: :continue),
        pool_factory: ->(_item_timeout) { fake_pool }, config: cfg
      )

      strategy.call([mutation("m1")], baseline_result: :baseline, integration: ->(_) { "cmd" })

      expect(pipeline).to have_received(:call).with(anything, baseline_result: :baseline)
    end

    it "does not start the pool when the cached results already reach fail-fast" do
      cfg_ff = Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, jobs: 2, fail_fast: 1)
      m1 = instance_double(Evilution::Mutation, file_path: "lib/foo.rb", to_s: "m1", unparseable?: true, strip_sources!: nil)
      notifier_spy = instance_spy(Evilution::Runner::MutationExecutor::ResultNotifier)
      allow(notifier_spy).to receive(:notify).and_return(:truncate)
      pool = fake_pool

      execution = strategy_for(pool, echo_isolator, config: cfg_ff, notifier: notifier_spy)
                  .call([m1, mutation("m2")], baseline_result: nil, integration: ->(_) { "cmd" })

      expect([pool.map_calls, execution.results.length, execution.truncated]).to eq([0, 1, true])
    end
  end

  it "calls isolator inside the pool for uncached mutations and rebuilds via packer" do
    m1 = mutation("m1")
    m2 = mutation("m2")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)

    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(m1), killed(m2))

    packer = Evilution::Runner::MutationExecutor::ResultPacker.new
    pool = fake_pool

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: packer,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier,
      pool_factory: ->(_item_timeout) { pool },
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
    pool = fake_pool(results: [Evilution::Parallel::WorkQueue::TIMED_OUT])

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier,
      pool_factory: ->(_item_timeout) { pool },
      config: cfg
    )

    execution = strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" })

    result = execution.results.first
    expect(result.status).to eq(:timeout)
    expect(result.mutation).to eq(m1)
    # Duration reflects the item_timeout the stuck worker exhausted (config
    # timeout 30 * 2), not a misleading 0.0 that would be cached/reported.
    expect(result.duration).to eq(60.0)
    expect(result.timings.to_h).to eq(test_run: 60.0)
    expect(result.time_limit).to eq(60.0)
  end

  it "translates an UNREADABLE pool sentinel into an :error result that says so" do
    m1 = mutation("m1")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    pool = fake_pool(results: [Evilution::Parallel::WorkQueue::UNREADABLE])

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: double(:isolator),
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier,
      pool_factory: ->(_item_timeout) { pool },
      config: cfg
    )

    execution = strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" })

    result = execution.results.first
    expect(result.status).to eq(:error)
    expect(result.error_message).to eq("worker's result could not be read; the worker was replaced")
    expect(result.error_class).to eq("Evilution::Error")
    expect(result.duration).to eq(0.0)
    expect(backend).not_to have_received(:store)
  end

  it "translates a DIED pool sentinel into an :error result" do
    m1 = mutation("m1")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    pool = fake_pool(results: [Evilution::Parallel::WorkQueue::DIED])

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier,
      pool_factory: ->(_item_timeout) { pool },
      config: cfg
    )

    execution = strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" })

    result = execution.results.first
    expect(result.status).to eq(:error)
    expect(result.error_message).to match(/worker process exited unexpectedly/)
    expect([result.error_class, result.duration]).to eq(["Evilution::Error", 0.0])
  end

  it "uses cached results in place of pool execution and preserves mutation order" do
    m1 = mutation("m1")
    m2 = mutation("m2")
    backend = instance_double("Cache")
    allow(backend).to receive(:fetch).with(m1).and_return(nil)
    allow(backend).to receive(:fetch).with(m2).and_return(status: :killed, duration: 0.5, killing_test: "k", test_command: "c")
    allow(backend).to receive(:store)

    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(m1))
    pool = fake_pool

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier,
      pool_factory: ->(_item_timeout) { pool },
      config: cfg
    )

    execution = strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })
    results = execution.results

    expect(results[0].status).to eq(:killed)
    expect(results[0].duration).to eq(0.1)
    expect(results[1].status).to eq(:killed)
    expect(results[1].duration).to eq(0.5)
  end

  it "stops running further mutations when notifier signals :truncate" do
    cfg_ff = Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, jobs: 1, fail_fast: 1)
    m1 = mutation("m1")
    m2 = mutation("m2")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(
      Evilution::Result::MutationResult.new(mutation: m1, status: :survived, duration: 0.01)
    )
    pool = fake_pool
    diags = Evilution::Runner::Diagnostics.new(cfg_ff)
    allow(diags).to receive(:log_memory)
    allow(diags).to receive(:log_worker_stats)

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: Evilution::Runner::MutationExecutor::ResultNotifier.new(cfg_ff, diagnostics: diags, on_result: nil),
      pool_factory: ->(_item_timeout) { pool },
      config: cfg_ff
    )

    execution = strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(execution.results.length).to eq(1)
    expect(execution.truncated).to be true
    expect(isolator).to have_received(:call).once
  end

  it "drops results after the one the notifier truncates on" do
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
    pool = fake_pool
    diags = Evilution::Runner::Diagnostics.new(cfg_ff)
    allow(diags).to receive(:log_memory)
    allow(diags).to receive(:log_worker_stats)

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: Evilution::Runner::MutationExecutor::ResultNotifier.new(cfg_ff, diagnostics: diags, on_result: nil),
      pool_factory: ->(_item_timeout) { pool },
      config: cfg_ff
    )

    execution = strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(execution.results.length).to eq(1)
    expect(execution.truncated).to be true
  end

  it "calls strip_sources! on every judged mutation and logs memory" do
    m1 = mutation("m1")
    expect(m1).to receive(:strip_sources!)

    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(m1))
    pool = fake_pool
    diags = diagnostics
    expect(diags).to receive(:log_memory).with("after batch", an_instance_of(String))

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier(diags),
      pool_factory: ->(_item_timeout) { pool },
      config: cfg,
      diagnostics: diags
    )

    strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" })
  end

  # EV-j0bv / GH #1607: a mutation the pool could not judge because of
  # infrastructure contention is re-run serially afterwards, which needs its
  # sources to still be there.
  it "keeps the sources of a mutation neutralised by an infra crash" do
    m1 = mutation("m1")
    expect(m1).not_to receive(:strip_sources!)

    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(infra_crash(m1))
    pool = fake_pool
    diags = diagnostics

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new(
        [Evilution::Runner::MutationExecutor::Neutralizer::InfraError.new]
      ),
      notifier: notifier(diags),
      pool_factory: ->(_item_timeout) { pool },
      config: cfg,
      diagnostics: diags
    )

    strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" })
  end

  # Only an infrastructure crash leaves the mutation unjudged; any other crash
  # is a verdict, so the sources go like those of any judged mutation.
  it "strips the sources of a mutation killed by a non-infrastructure crash" do
    m1 = mutation("m1")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(
      Evilution::Result::MutationResult.new(
        mutation: m1, status: :killed, duration: 0.1, test_command: "c",
        error: Evilution::Result::ErrorInfo.new(klass: "RuntimeError", message: "boom")
      )
    )
    pool = fake_pool
    diags = diagnostics

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier(diags),
      pool_factory: ->(_item_timeout) { pool },
      config: cfg,
      diagnostics: diags
    )

    strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(m1).to have_received(:strip_sources!)
  end

  it "starts the notifier with the mutation count and finishes it" do
    m1 = mutation("m1")
    m2 = mutation("m2")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(m1), killed(m2))
    pool = fake_pool

    notifier_spy = instance_spy(Evilution::Runner::MutationExecutor::ResultNotifier)
    allow(notifier_spy).to receive(:notify).and_return(:continue)

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier_spy,
      pool_factory: ->(_item_timeout) { pool },
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
    pool = fake_pool

    notifier_spy = instance_spy(Evilution::Runner::MutationExecutor::ResultNotifier)
    allow(notifier_spy).to receive(:notify).and_return(:continue)

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier_spy,
      pool_factory: ->(_item_timeout) { pool },
      config: cfg
    )

    strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(notifier_spy).to have_received(:notify).with(an_instance_of(Evilution::Result::MutationResult), 1).ordered
    expect(notifier_spy).to have_received(:notify).with(an_instance_of(Evilution::Result::MutationResult), 2).ordered
  end

  it "aggregates worker stats by pid and logs them via diagnostics" do
    cfg_j1 = Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, jobs: 1, timeout: 30)
    m1 = mutation("m1")
    m2 = mutation("m2")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(m1), killed(m2))
    stat = Evilution::Parallel::WorkQueue::WorkerStat
    pool = fake_pool(worker_stats: [stat.new(7, 1, 1.0, 2.0), stat.new(7, 1, 0.5, 1.0)])

    diags = Evilution::Runner::Diagnostics.new(cfg_j1)
    allow(diags).to receive(:log_memory)
    allow(diags).to receive(:log_worker_stats)

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier(diags),
      pool_factory: ->(_item_timeout) { pool },
      config: cfg_j1,
      diagnostics: diags
    )

    strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(diags).to have_received(:log_worker_stats).with([stat.new(7, 2, 1.5, 3.0)])
  end

  it "does not call worker diagnostics when no diagnostics object is provided" do
    m1 = mutation("m1")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(m1))
    pool = fake_pool

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier,
      pool_factory: ->(_item_timeout) { pool },
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
    pool = fake_pool

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: pipeline,
      notifier: notifier,
      pool_factory: ->(_item_timeout) { pool },
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
    pool = fake_pool

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier,
      pool_factory: ->(_item_timeout) { pool },
      config: cfg
    )

    strategy.call([m1], baseline_result: nil, integration: ->(m) { "test-cmd-for-#{m}" })

    expect(captured_command).to eq("test-cmd-for-m1")
  end

  it "passes individual mutations (not indices or the whole list) to the pool" do
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
    pool = fake_pool

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier,
      pool_factory: ->(_item_timeout) { pool },
      config: cfg
    )

    strategy.call([m1, m2], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(isolated).to eq([m1, m2])
  end

  it "does not invoke the pool when every mutation is cached" do
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
      pool_factory: ->(_item_timeout) { pool },
      config: cfg
    )

    execution = strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(pool).not_to have_received(:map)
    expect(execution.results.map(&:status)).to eq(%i[killed])
  end

  it "logs the completed count (not the whole state hash) in the memory log" do
    m1 = mutation("m1")
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(m1))
    pool = fake_pool
    diags = diagnostics
    expect(diags).to receive(:log_memory).with("after batch", "1 complete")

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier(diags),
      pool_factory: ->(_item_timeout) { pool },
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
    pool = fake_pool

    strategy = described_class.new(
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      isolator: isolator,
      packer: Evilution::Runner::MutationExecutor::ResultPacker.new,
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier,
      pool_factory: ->(_item_timeout) { pool },
      config: cfg
    )

    strategy.call([m1], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(call_order).to eq(%i[store strip])
  end
end
