# frozen_string_literal: true

require "evilution/config"
require "evilution/runner/mutation_executor"
require "evilution/runner/diagnostics"
require "evilution/runner/baseline_runner"

# Coordinator-level smoke tests. Detailed behavior of collaborators is covered by:
#   spec/evilution/runner/mutation_executor/result_cache_spec.rb
#   spec/evilution/runner/mutation_executor/result_packer_spec.rb
#   spec/evilution/runner/mutation_executor/result_notifier_spec.rb
#   spec/evilution/runner/mutation_executor/mutation_runner_spec.rb
#   spec/evilution/runner/mutation_executor/neutralization_pipeline_spec.rb
#   spec/evilution/runner/mutation_executor/neutralizer/infra_error_spec.rb
#   spec/evilution/runner/mutation_executor/neutralizer/baseline_failed_spec.rb
#   spec/evilution/runner/mutation_executor/strategy/sequential_spec.rb
#   spec/evilution/runner/mutation_executor/strategy/parallel_spec.rb
RSpec.describe Evilution::Runner::MutationExecutor do
  def config(**overrides)
    Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, **overrides)
  end

  def build(cfg, isolator:, cache: nil, on_result: nil, hooks: nil,
            baseline_runner: default_baseline_runner)
    described_class.new(
      cfg,
      isolator: isolator,
      baseline_runner: baseline_runner,
      cache: cache,
      hooks: hooks,
      diagnostics: Evilution::Runner::Diagnostics.new(cfg),
      on_result: on_result
    )
  end

  def default_baseline_runner
    instance_double(
      Evilution::Runner::BaselineRunner,
      build_integration: ->(_m) { "cmd" },
      neutralization_resolver: ->(_f) {},
      neutralization_fallback_dir: "spec"
    )
  end

  def mutation(file: "lib/foo.rb", identifier: nil, unparseable: false)
    @mut_id ||= 0
    @mut_id += 1
    id = identifier || "Foo#bar:#{@mut_id}"
    instance_double(
      Evilution::Mutation, file_path: file, to_s: id,
                           strip_sources!: nil, unparseable?: unparseable
    )
  end

  def killed_result(mutation)
    Evilution::Result::MutationResult.new(mutation: mutation, status: :killed, duration: 0.01)
  end

  def survived_result(mutation)
    Evilution::Result::MutationResult.new(mutation: mutation, status: :survived, duration: 0.01)
  end

  def error_result(mutation, error_class:, error_message: "boom", error_backtrace: [])
    Evilution::Result::MutationResult.new(
      mutation: mutation, status: :error, duration: 0.01,
      error: Evilution::Result::ErrorInfo.new(
        klass: error_class, message: error_message, backtrace: error_backtrace
      )
    )
  end

  describe "#call" do
    it "returns ExecutionResult in sequential mode (jobs == 1)" do
      cfg = config(jobs: 1)
      mutations = [mutation, mutation]
      isolator = instance_double(Evilution::Isolation::Fork)
      allow(isolator).to receive(:call) { |mutation:, **| killed_result(mutation) }

      execution = build(cfg, isolator: isolator).call(mutations, nil)

      expect(execution.results.length).to eq(2)
      expect(execution.results).to all(be_killed)
      expect(execution.truncated).to be(false)
    end

    it "dispatches to the parallel strategy when jobs > 1" do
      cfg = config(jobs: 2)
      mutations = [mutation, mutation]
      isolator = instance_double(Evilution::Isolation::Fork)
      allow(isolator).to receive(:call) { |mutation:, **| killed_result(mutation) }

      parallel_strategy = instance_double(Evilution::Runner::MutationExecutor::Strategy::Parallel)
      allow(parallel_strategy).to receive(:call).and_return(
        Evilution::Runner::MutationExecutor::ExecutionResult.new(results: [], truncated: false)
      )
      expect(Evilution::Runner::MutationExecutor::Strategy::Parallel).to receive(:new).and_return(parallel_strategy)

      build(cfg, isolator: isolator).call(mutations, nil)
    end

    it "dispatches to the sequential strategy when jobs == 1" do
      cfg = config(jobs: 1)
      mutations = [mutation]
      isolator = instance_double(Evilution::Isolation::Fork)
      allow(isolator).to receive(:call) { |mutation:, **| killed_result(mutation) }

      sequential_strategy = instance_double(Evilution::Runner::MutationExecutor::Strategy::Sequential)
      allow(sequential_strategy).to receive(:call).and_return(
        Evilution::Runner::MutationExecutor::ExecutionResult.new(results: [], truncated: false)
      )
      expect(Evilution::Runner::MutationExecutor::Strategy::Sequential).to receive(:new).and_return(sequential_strategy)

      build(cfg, isolator: isolator).call(mutations, nil)
    end

    it "invokes on_result for each mutation result" do
      cfg = config(jobs: 1)
      mutations = [mutation, mutation]
      isolator = instance_double(Evilution::Isolation::Fork)
      allow(isolator).to receive(:call) { |mutation:, **| killed_result(mutation) }
      captured = []

      build(cfg, isolator: isolator, on_result: ->(r) { captured << r }).call(mutations, nil)

      expect(captured.length).to eq(2)
    end

    it "short-circuits unparseable mutations in sequential mode without invoking isolator" do
      cfg = config(jobs: 1)
      parseable = mutation
      unparseable = mutation(unparseable: true)
      isolator = instance_double(Evilution::Isolation::Fork)
      allow(isolator).to receive(:call) { |mutation:, **| killed_result(mutation) }

      execution = build(cfg, isolator: isolator).call([parseable, unparseable], nil)

      expect(isolator).to have_received(:call).once
      expect(execution.results.map(&:status)).to eq(%i[killed unparseable])
    end

    it "short-circuits unparseable mutations in parallel mode without dispatching to pool" do
      cfg = config(jobs: 2)
      mutations = [mutation(unparseable: true), mutation(unparseable: true)]
      isolator = instance_double(Evilution::Isolation::Fork)

      execution = build(cfg, isolator: isolator).call(mutations, nil)

      expect(execution.results.map(&:status)).to eq(%i[unparseable unparseable])
    end

    it "wires up the neutralization pipeline (infra-error + baseline-failed mixed batch)" do
      cfg = config(jobs: 1)
      infra_mut = mutation(file: "lib/foo.rb")
      baseline_mut = mutation(file: "lib/foo.rb")
      isolator = instance_double(Evilution::Isolation::Fork)
      allow(isolator).to receive(:call) do |mutation:, **|
        if mutation.equal?(infra_mut)
          error_result(infra_mut, error_class: "LoadError",
                                  error_backtrace: ["spec/spec_helper.rb:3:in `require'"])
        else
          survived_result(baseline_mut)
        end
      end
      baseline = instance_double(Evilution::Baseline::Result, failed?: true, failed_spec_files: ["spec"])

      execution = build(cfg, isolator: isolator).call([infra_mut, baseline_mut], baseline)

      expect(execution.results.map(&:status)).to eq(%i[neutral neutral])
    end

    it "feeds the built integration into the test command, not the baseline runner" do
      cfg = config(jobs: 1)
      mut = mutation
      captured = nil
      isolator = instance_double(Evilution::Isolation::Fork)
      allow(isolator).to receive(:call) do |mutation:, test_command:, **|
        captured = test_command.call(mutation)
        killed_result(mutation)
      end

      build(cfg, isolator: isolator).call([mut], nil)

      expect(captured).to eq("cmd")
    end

    it "uses the baseline neutralization resolver only when the baseline failed" do
      cfg = config(jobs: 1)
      mut = mutation(file: "lib/foo.rb")
      baseline_runner = instance_double(
        Evilution::Runner::BaselineRunner,
        build_integration: ->(_m) { "cmd" },
        neutralization_resolver: ->(_f) { "spec/resolved_spec.rb" },
        neutralization_fallback_dir: "spec/fallback"
      )
      isolator = instance_double(Evilution::Isolation::Fork)
      allow(isolator).to receive(:call) { |mutation:, **| survived_result(mutation) }
      baseline = instance_double(
        Evilution::Baseline::Result, failed?: true,
                                     failed_spec_files: ["spec/resolved_spec.rb"]
      )

      execution = build(cfg, isolator: isolator, baseline_runner: baseline_runner)
                  .call([mut], baseline)

      expect(execution.results.map(&:status)).to eq([:neutral])
    end
  end

  describe "parallel pool construction" do
    def capture_pool_factory(cfg, hooks:)
      isolator = instance_double(Evilution::Isolation::Fork)
      parallel = instance_double(Evilution::Runner::MutationExecutor::Strategy::Parallel)
      allow(parallel).to receive(:call).and_return(
        Evilution::Runner::MutationExecutor::ExecutionResult.new(results: [], truncated: false)
      )
      factory = nil
      allow(Evilution::Runner::MutationExecutor::Strategy::Parallel).to receive(:new) do |**kwargs|
        factory = kwargs[:pool_factory]
        parallel
      end
      build(cfg, isolator: isolator, hooks: hooks).call([mutation], nil)
      factory
    end

    it "passes the configured hooks through to the pool" do
      hooks = Object.new
      pool = instance_double(Evilution::Parallel::Pool)
      allow(Evilution::Parallel::Pool).to receive(:new).and_return(pool)

      capture_pool_factory(config(jobs: 2), hooks: hooks).call

      expect(Evilution::Parallel::Pool).to have_received(:new).with(hash_including(hooks: hooks))
    end

    it "sets the pool item timeout to double the configured timeout" do
      pool = instance_double(Evilution::Parallel::Pool)
      allow(Evilution::Parallel::Pool).to receive(:new).and_return(pool)

      capture_pool_factory(config(jobs: 2, timeout: 9), hooks: nil).call

      expect(Evilution::Parallel::Pool).to have_received(:new).with(hash_including(item_timeout: 18))
    end

    it "leaves the pool item timeout nil when no timeout is configured" do
      pool = instance_double(Evilution::Parallel::Pool)
      allow(Evilution::Parallel::Pool).to receive(:new).and_return(pool)

      capture_pool_factory(config(jobs: 2, timeout: nil), hooks: nil).call

      expect(Evilution::Parallel::Pool).to have_received(:new).with(hash_including(item_timeout: nil))
    end
  end
end
