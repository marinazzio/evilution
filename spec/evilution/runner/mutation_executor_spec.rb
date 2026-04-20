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
      error_class: error_class, error_message: error_message, error_backtrace: error_backtrace
    )
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

    it "short-circuits unparseable mutations in sequential path without invoking isolator" do
      cfg = config(jobs: 1)
      parseable = mutation
      unparseable = mutation(unparseable: true)
      isolator = instance_double(Evilution::Isolation::Fork)
      allow(isolator).to receive(:call) { |mutation:, **| killed_result(mutation) }

      executor = build(cfg, isolator: isolator)
      results, = executor.call([parseable, unparseable], nil)

      expect(isolator).to have_received(:call).once
      expect(results.map(&:status)).to eq(%i[killed unparseable])
    end

    it "short-circuits unparseable mutations in parallel path without dispatching to pool" do
      cfg = config(jobs: 2)
      mutations = [mutation(unparseable: true), mutation(unparseable: true)]
      isolator = instance_double(Evilution::Isolation::Fork)

      executor = build(cfg, isolator: isolator)
      results, = executor.call(mutations, nil)

      expect(results.map(&:status)).to eq(%i[unparseable unparseable])
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

    describe "infra-error neutralization" do
      it "neutralizes :error results with error_class LoadError" do
        cfg = config(jobs: 1)
        m = mutation
        isolator = instance_double(Evilution::Isolation::Fork)
        allow(isolator).to receive(:call).and_return(
          error_result(m, error_class: "LoadError", error_message: "cannot load such file -- missing_gem")
        )

        results, = build(cfg, isolator: isolator).call([m], nil)

        expect(results.first.status).to eq(:neutral)
      end

      it "neutralizes :error NameError when backtrace references spec_helper" do
        cfg = config(jobs: 1)
        m = mutation
        isolator = instance_double(Evilution::Isolation::Fork)
        allow(isolator).to receive(:call).and_return(
          error_result(m, error_class: "NameError",
                          error_backtrace: ["spec/spec_helper.rb:15:in `<top (required)>'"])
        )

        results, = build(cfg, isolator: isolator).call([m], nil)

        expect(results.first.status).to eq(:neutral)
      end

      it "neutralizes :error NameError when backtrace references rails_helper" do
        cfg = config(jobs: 1)
        m = mutation
        isolator = instance_double(Evilution::Isolation::Fork)
        allow(isolator).to receive(:call).and_return(
          error_result(m, error_class: "NameError",
                          error_backtrace: ["spec/rails_helper.rb:8:in `block'"])
        )

        results, = build(cfg, isolator: isolator).call([m], nil)

        expect(results.first.status).to eq(:neutral)
      end

      it "neutralizes :error NameError when backtrace references spec/support" do
        cfg = config(jobs: 1)
        m = mutation
        isolator = instance_double(Evilution::Isolation::Fork)
        allow(isolator).to receive(:call).and_return(
          error_result(m, error_class: "NameError",
                          error_backtrace: ["spec/support/fixture_helpers.rb:42:in `let_it_be'"])
        )

        results, = build(cfg, isolator: isolator).call([m], nil)

        expect(results.first.status).to eq(:neutral)
      end

      it "keeps :error NameError with backtrace only in lib/ as error (mutation-caused)" do
        cfg = config(jobs: 1)
        m = mutation
        isolator = instance_double(Evilution::Isolation::Fork)
        allow(isolator).to receive(:call).and_return(
          error_result(m, error_class: "NameError",
                          error_backtrace: ["lib/foo.rb:10:in `bar'", "lib/foo.rb:20:in `baz'"])
        )

        results, = build(cfg, isolator: isolator).call([m], nil)

        expect(results.first.status).to eq(:error)
      end

      it "keeps :error ArgumentError as error (not in infra allowlist)" do
        cfg = config(jobs: 1)
        m = mutation
        isolator = instance_double(Evilution::Isolation::Fork)
        allow(isolator).to receive(:call).and_return(
          error_result(m, error_class: "ArgumentError",
                          error_backtrace: ["spec/spec_helper.rb:1:in `<top>'"])
        )

        results, = build(cfg, isolator: isolator).call([m], nil)

        expect(results.first.status).to eq(:error)
      end

      it "does not affect non-error statuses" do
        cfg = config(jobs: 1)
        m = mutation
        isolator = instance_double(Evilution::Isolation::Fork)
        allow(isolator).to receive(:call).and_return(killed_result(m))

        results, = build(cfg, isolator: isolator).call([m], nil)

        expect(results.first.status).to eq(:killed)
      end
    end
  end
end
