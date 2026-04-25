# frozen_string_literal: true

require "evilution/config"
require "evilution/mutation"
require "evilution/result/mutation_result"
require "evilution/runner/diagnostics"
require "evilution/runner/mutation_executor/result_cache"
require "evilution/runner/mutation_executor/result_notifier"
require "evilution/runner/mutation_executor/mutation_runner"
require "evilution/runner/mutation_executor/neutralization_pipeline"
require "evilution/runner/mutation_executor/strategy/sequential"

RSpec.describe Evilution::Runner::MutationExecutor::Strategy::Sequential do
  let(:cfg) { Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, timeout: 30) }

  def mutation(id, file: "lib/foo.rb", unparseable: false)
    instance_double(Evilution::Mutation, file_path: file, to_s: id, unparseable?: unparseable, strip_sources!: nil)
  end

  def killed(mut)
    Evilution::Result::MutationResult.new(mutation: mut, status: :killed, duration: 0.01, test_command: "c")
  end

  def survived(mut)
    Evilution::Result::MutationResult.new(mutation: mut, status: :survived, duration: 0.01)
  end

  def runner_returning(*results)
    queue = results.dup
    runner = double(:runner)
    allow(runner).to receive(:call) { |_mut, **| queue.shift }
    runner
  end

  def passthrough_pipeline
    Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([])
  end

  def notifier(config: cfg, on_result: nil)
    Evilution::Runner::MutationExecutor::ResultNotifier.new(
      config,
      hooks: nil,
      diagnostics: Evilution::Runner::Diagnostics.new(config),
      on_result: on_result
    )
  end

  it "iterates mutations, calls strip_sources! per mutation, and returns [results, false]" do
    m1 = mutation("m1")
    m2 = mutation("m2")
    expect(m1).to receive(:strip_sources!)
    expect(m2).to receive(:strip_sources!)

    strategy = described_class.new(
      runner: runner_returning(killed(m1), killed(m2)),
      pipeline: passthrough_pipeline,
      notifier: notifier
    )

    integration = ->(_) { "cmd" }
    results, truncated = strategy.call([m1, m2], baseline_result: nil, integration: integration)

    expect(results.map(&:status)).to eq(%i[killed killed])
    expect(truncated).to be false
  end

  it "stops early and returns truncated=true when notifier signals :truncate" do
    m1 = mutation("m1")
    m2 = mutation("m2")
    m3 = mutation("m3")

    strategy = described_class.new(
      runner: runner_returning(survived(m1), survived(m2), survived(m3)),
      pipeline: passthrough_pipeline,
      notifier: notifier(config: Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, fail_fast: 2))
    )

    results, truncated = strategy.call([m1, m2, m3], baseline_result: nil, integration: ->(_) { "cmd" })

    expect(results.length).to eq(2)
    expect(truncated).to be true
  end

  it "applies the pipeline to each result" do
    m1 = mutation("m1")
    nz = double(:neutralizer)
    allow(nz).to receive(:call).and_return(killed(m1))
    pipeline = Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([nz])

    strategy = described_class.new(
      runner: runner_returning(survived(m1)),
      pipeline: pipeline,
      notifier: notifier
    )

    results, = strategy.call([m1], baseline_result: :baseline, integration: ->(_) { "cmd" })

    expect(results.first.status).to eq(:killed)
    expect(nz).to have_received(:call).with(an_instance_of(Evilution::Result::MutationResult), baseline_result: :baseline)
  end
end
