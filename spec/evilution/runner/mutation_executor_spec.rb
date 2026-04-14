# frozen_string_literal: true

require "evilution/config"
require "evilution/runner/mutation_executor"
require "evilution/runner/diagnostics"
require "evilution/runner/baseline_runner"

RSpec.describe Evilution::Runner::MutationExecutor do
  def config(**overrides)
    Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, **overrides)
  end

  def build(cfg, isolator:, cache: nil, on_result: nil)
    described_class.new(
      cfg,
      isolator: isolator,
      baseline_runner: instance_double(
        Evilution::Runner::BaselineRunner,
        build_integration: ->(_m) { "cmd" },
        neutralization_resolver: ->(_f) {},
        neutralization_fallback_dir: "spec"
      ),
      cache: cache,
      hooks: nil,
      diagnostics: Evilution::Runner::Diagnostics.new(cfg),
      on_result: on_result
    )
  end

  def mutation(file: "lib/foo.rb", identifier: nil)
    @mut_id ||= 0
    @mut_id += 1
    id = identifier || "Foo#bar:#{@mut_id}"
    instance_double(
      Evilution::Mutation, file_path: file, to_s: id,
                           strip_sources!: nil
    )
  end

  def killed_result(mutation)
    Evilution::Result::MutationResult.new(mutation: mutation, status: :killed, duration: 0.01)
  end

  def survived_result(mutation)
    Evilution::Result::MutationResult.new(mutation: mutation, status: :survived, duration: 0.01)
  end

  describe "#call" do
    it "runs mutations sequentially when config.jobs is 1 and returns results + truncated flag" do
      cfg = config(jobs: 1)
      mutations = [mutation, mutation]
      isolator = instance_double(Evilution::Isolation::Fork)
      allow(isolator).to receive(:call) { |mutation:, **| killed_result(mutation) }

      executor = build(cfg, isolator: isolator)
      results, truncated = executor.call(mutations, nil)

      expect(results.length).to eq(2)
      expect(results).to all(be_killed)
      expect(truncated).to be(false)
    end

    it "stops early when fail_fast is reached" do
      cfg = config(jobs: 1, fail_fast: 1)
      mutations = [mutation, mutation, mutation]
      isolator = instance_double(Evilution::Isolation::Fork)
      allow(isolator).to receive(:call) { |mutation:, **| survived_result(mutation) }

      executor = build(cfg, isolator: isolator)
      results, truncated = executor.call(mutations, nil)

      expect(truncated).to be(true)
      expect(results.length).to eq(1)
    end

    it "invokes on_result for each mutation result" do
      cfg = config(jobs: 1)
      mutations = [mutation, mutation]
      isolator = instance_double(Evilution::Isolation::Fork)
      allow(isolator).to receive(:call) { |mutation:, **| killed_result(mutation) }
      captured = []

      executor = build(cfg, isolator: isolator, on_result: ->(r) { captured << r })
      executor.call(mutations, nil)

      expect(captured.length).to eq(2)
    end

    it "strips mutation sources after executing each result" do
      cfg = config(jobs: 1)
      m = mutation
      isolator = instance_double(Evilution::Isolation::Fork)
      allow(isolator).to receive(:call).and_return(killed_result(m))
      expect(m).to receive(:strip_sources!)

      build(cfg, isolator: isolator).call([m], nil)
    end

    it "neutralizes survivors when baseline is failed for the spec file" do
      cfg = config(jobs: 1)
      m = mutation(file: "lib/foo.rb")
      isolator = instance_double(Evilution::Isolation::Fork)
      allow(isolator).to receive(:call).and_return(survived_result(m))
      baseline = instance_double(Evilution::Baseline::Result, failed?: true, failed_spec_files: ["spec"])

      executor = build(cfg, isolator: isolator)
      results, = executor.call([m], baseline)

      expect(results.first.status).to eq(:neutral)
    end
  end
end
