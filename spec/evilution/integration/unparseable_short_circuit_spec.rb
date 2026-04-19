# frozen_string_literal: true

require "evilution/config"
require "evilution/ast/parser"
require "evilution/mutator/registry"
require "evilution/runner/mutation_executor"
require "evilution/runner/diagnostics"
require "evilution/runner/baseline_runner"
require "evilution/isolation/fork"

RSpec.describe "Unparseable mutation short-circuit" do
  let(:fixture_path) { File.expand_path("../../support/fixtures/unparseable_mutation.rb", __dir__) }

  def executor_with_spy_isolator(isolator)
    cfg = Evilution::Config.new(quiet: true, jobs: 1, baseline: false, skip_config_file: true, timeout: 30)
    Evilution::Runner::MutationExecutor.new(
      cfg,
      isolator: isolator,
      baseline_runner: instance_double(
        Evilution::Runner::BaselineRunner,
        build_integration: ->(_m) { "cmd" },
        neutralization_resolver: ->(_f) {},
        neutralization_fallback_dir: "spec"
      ),
      cache: nil,
      hooks: nil,
      diagnostics: Evilution::Runner::Diagnostics.new(cfg),
      on_result: nil
    )
  end

  it "classifies unparseable mutations without invoking the isolator or waiting for timeout" do
    subjects = Evilution::AST::Parser.new.call(fixture_path)
    mutations = subjects.flat_map { |s| Evilution::Mutator::Registry.default.mutations_for(s) }
    unparseable = mutations.select(&:unparseable?)

    expect(unparseable).not_to be_empty,
                               "fixture must produce at least one unparseable mutation for this guard to be meaningful"

    isolator = instance_double(Evilution::Isolation::Fork)
    allow(isolator).to receive(:call)
    executor = executor_with_spy_isolator(isolator)

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    results, = executor.call(unparseable, nil)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    expect(results.map(&:status)).to all(eq(:unparseable))
    expect(isolator).not_to have_received(:call)
    expect(elapsed).to be < 1.0
  end
end
