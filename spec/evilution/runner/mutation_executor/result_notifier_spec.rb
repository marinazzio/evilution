# frozen_string_literal: true

require "evilution/config"
require "evilution/result/mutation_result"
require "evilution/runner/diagnostics"
require "evilution/runner/mutation_executor/result_notifier"

RSpec.describe Evilution::Runner::MutationExecutor::ResultNotifier do
  def cfg(**overrides)
    Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, **overrides)
  end

  def mutation
    instance_double("Mutation")
  end

  def survived(mut = mutation)
    Evilution::Result::MutationResult.new(mutation: mut, status: :survived, duration: 0.01)
  end

  def killed(mut = mutation)
    Evilution::Result::MutationResult.new(mutation: mut, status: :killed, duration: 0.01)
  end

  def diagnostics
    Evilution::Runner::Diagnostics.new(cfg)
  end

  it "calls on_result for each result" do
    seen = []
    nf = described_class.new(cfg, diagnostics: diagnostics, on_result: ->(r) { seen << r.status })
    nf.start(2)
    nf.notify(killed, 1)
    nf.notify(survived, 2)
    nf.finish

    expect(seen).to eq(%i[killed survived])
  end

  it "delegates progress and mutation diagnostics to diagnostics" do
    diags = diagnostics
    expect(diags).to receive(:log_progress).with(1, :killed)
    expect(diags).to receive(:log_mutation_diagnostics).with(an_instance_of(Evilution::Result::MutationResult))

    nf = described_class.new(cfg, diagnostics: diags, on_result: nil)
    nf.start(1)
    nf.notify(killed, 1)
    nf.finish
  end

  it "returns :continue when fail_fast is disabled" do
    nf = described_class.new(cfg, diagnostics: diagnostics, on_result: nil)
    nf.start(3)
    expect(nf.notify(survived, 1)).to eq(:continue)
    expect(nf.notify(survived, 2)).to eq(:continue)
  end

  it "returns :truncate after survived_count >= config.fail_fast" do
    nf = described_class.new(cfg(fail_fast: 2), diagnostics: diagnostics, on_result: nil)
    nf.start(5)
    expect(nf.notify(survived, 1)).to eq(:continue)
    expect(nf.notify(survived, 2)).to eq(:truncate)
  end

  it "does not count killed results toward survived" do
    nf = described_class.new(cfg(fail_fast: 1), diagnostics: diagnostics, on_result: nil)
    nf.start(3)
    expect(nf.notify(killed, 1)).to eq(:continue)
    expect(nf.notify(killed, 2)).to eq(:continue)
    expect(nf.notify(survived, 3)).to eq(:truncate)
  end

  it "is safe with on_result: nil (no error, returns control signal)" do
    nf = described_class.new(cfg, diagnostics: diagnostics, on_result: nil)
    nf.start(1)
    expect { nf.notify(killed, 1) }.not_to raise_error
  end
end
