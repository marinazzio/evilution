# frozen_string_literal: true

require "evilution/config"
require "evilution/runner/mutation_executor"
require "evilution/runner/diagnostics"
require "evilution/runner/baseline_runner"
require "evilution/result/summary"
require "evilution/result/mutation_result"

# Integration spec for EV-rf98 (GH #759): asserts that a `let_it_be`-style
# collision (second `before(:all)` raising NameError from a spec/support frame)
# flows from the isolator through MutationExecutor → Summary as :neutral, and
# is excluded from the kill-rate denominator — i.e. the fixture collision does
# not contaminate the mutation score.
#
# Simulates the collision via a stubbed :error result whose origin frame lives
# in spec/support/; MutationExecutor's infra-error classifier (EV-9vq4) does
# not require the raiser to actually be let_it_be — the origin regex is what
# matters.
RSpec.describe "let_it_be collision neutralization end-to-end" do
  def config(**overrides)
    Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, **overrides)
  end

  def mutation(id:)
    instance_double(
      Evilution::Mutation,
      file_path: "lib/foo.rb",
      to_s: "Foo#bar:#{id}",
      strip_sources!: nil,
      unparseable?: false
    )
  end

  def error_result(mutation, backtrace:)
    Evilution::Result::MutationResult.new(
      mutation: mutation,
      status: :error,
      duration: 0.01,
      error_class: "NameError",
      error_message: "undefined method `let_it_be' for ...",
      error_backtrace: backtrace
    )
  end

  def killed_result(mutation)
    Evilution::Result::MutationResult.new(mutation: mutation, status: :killed, duration: 0.01)
  end

  def build_executor(cfg, isolator:)
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

  let(:let_it_be_backtrace) do
    [
      "spec/support/fixture_helpers.rb:42:in `let_it_be'",
      "spec/support/fixture_helpers.rb:30:in `block in setup'",
      "spec/foo_spec.rb:5:in `<top (required)>'"
    ]
  end

  it "marks let_it_be-origin NameError as :neutral in executor results" do
    cfg = config(jobs: 1)
    m = mutation(id: 1)
    isolator = instance_double(Evilution::Isolation::Fork)
    allow(isolator).to receive(:call).and_return(error_result(m, backtrace: let_it_be_backtrace))

    results, = build_executor(cfg, isolator: isolator).call([m], nil)

    expect(results.first.status).to eq(:neutral)
  end

  it "excludes the let_it_be-collision neutral from Summary#score_denominator" do
    cfg = config(jobs: 1)
    killed_mut = mutation(id: 1)
    infra_mut = mutation(id: 2)
    isolator = instance_double(Evilution::Isolation::Fork)
    allow(isolator).to receive(:call) do |mutation:, **|
      mutation.to_s == "Foo#bar:1" ? killed_result(mutation) : error_result(mutation, backtrace: let_it_be_backtrace)
    end

    results, = build_executor(cfg, isolator: isolator).call([killed_mut, infra_mut], nil)
    summary = Evilution::Result::Summary.new(results: results)

    expect(summary.neutral).to eq(1)
    expect(summary.score_denominator).to eq(1)
    expect(summary.score).to eq(1.0)
  end

  it "does not penalize the score when all mutations hit a let_it_be collision" do
    cfg = config(jobs: 1)
    mutations = [mutation(id: 1), mutation(id: 2)]
    isolator = instance_double(Evilution::Isolation::Fork)
    allow(isolator).to receive(:call) do |mutation:, **|
      error_result(mutation, backtrace: let_it_be_backtrace)
    end

    results, = build_executor(cfg, isolator: isolator).call(mutations, nil)
    summary = Evilution::Result::Summary.new(results: results)

    expect(summary.neutral).to eq(2)
    expect(summary.errors).to eq(0)
    expect(summary.score_denominator).to eq(0)
    expect(summary.score).to eq(0.0)
  end
end
