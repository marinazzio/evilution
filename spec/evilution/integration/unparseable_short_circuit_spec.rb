# frozen_string_literal: true

require "evilution/config"
require "evilution/ast/parser"
require "evilution/mutator/base"
require "evilution/runner/mutation_executor"
require "evilution/runner/diagnostics"
require "evilution/runner/baseline_runner"
require "evilution/isolation/fork"

RSpec.describe "Unparseable mutation short-circuit" do
  let(:fixture_path) { File.expand_path("../../support/fixtures/unparseable_mutation.rb", __dir__) }

  # A synthetic operator that emits a deliberately-unparseable mutation. Used
  # in place of the production mutator registry so the test doesn't depend on
  # any specific operator continuing to produce unparseable bytes — operator
  # bug fixes (EV-bjot, EV-kws8, EV-05tp, EV-jjpt, ...) keep eliminating the
  # accidental unparseable sources this guard used to rely on. Synthesizing
  # the case here keeps the regression test stable across operator fixes.
  let(:unparseable_mutator_class) do
    Class.new(Evilution::Mutator::Base) do
      def visit_def_node(node)
        add_mutation(
          offset: node.location.start_offset,
          length: node.location.length,
          # `def` keyword on its own is unbalanced — Prism rejects it.
          replacement: "def",
          node: node
        )

        super
      end
    end
  end

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
    mutations = subjects.flat_map { |s| unparseable_mutator_class.new.call(s) }
    unparseable = mutations.select(&:unparseable?)

    expect(unparseable).not_to be_empty,
                               "synthetic operator must produce at least one unparseable mutation for this guard to be meaningful"

    isolator = instance_double(Evilution::Isolation::Fork)
    allow(isolator).to receive(:call)
    executor = executor_with_spy_isolator(isolator)

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    execution = executor.call(unparseable, nil)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    expect(execution.results.map(&:status)).to all(eq(:unparseable))
    expect(isolator).not_to have_received(:call)
    expect(elapsed).to be < 1.0
  end
end
