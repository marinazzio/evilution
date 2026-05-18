# frozen_string_literal: true

require "stringio"
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

  it "initializes survived_count to 0 before start is called" do
    nf = described_class.new(cfg, diagnostics: diagnostics, on_result: nil)
    expect(nf.survived_count).to eq(0)
  end

  it "resets survived_count to 0 on each start" do
    nf = described_class.new(cfg, diagnostics: diagnostics, on_result: nil)
    nf.start(3)
    nf.notify(survived, 1)
    nf.notify(survived, 2)
    expect(nf.survived_count).to eq(2)

    nf.start(3)
    expect(nf.survived_count).to eq(0)
  end

  context "with a progress bar (text format, progress enabled, tty stderr)" do
    def fake_tty
      io = StringIO.new
      def io.tty?
        true
      end
      io
    end

    def progress_cfg
      Evilution::Config.new(baseline: false, skip_config_file: true, progress: true, format: :text)
    end

    around do |example|
      original = $stderr
      $stderr = fake_tty
      example.run
      $stderr = original
    end

    it "builds a progress bar when all conditions are met" do
      nf = described_class.new(progress_cfg, diagnostics: diagnostics, on_result: nil)
      nf.start(2)
      nf.notify(killed, 1)
      expect($stderr.string).to include("1/2 mutations")
    end

    it "ticks the progress bar with the result status on notify" do
      nf = described_class.new(progress_cfg, diagnostics: diagnostics, on_result: nil)
      nf.start(2)
      nf.notify(survived, 1)
      expect($stderr.string).to include("1 survived")
    end

    it "finishes the progress bar, emitting a trailing newline" do
      nf = described_class.new(progress_cfg, diagnostics: diagnostics, on_result: nil)
      nf.start(1)
      nf.notify(killed, 1)
      $stderr.truncate(0)
      $stderr.rewind
      nf.finish
      expect($stderr.string).to end_with("\n")
      expect($stderr.string).not_to be_empty
    end

    it "does not build a progress bar when progress is disabled" do
      cfg_no_progress = Evilution::Config.new(
        baseline: false, skip_config_file: true, progress: false, format: :text
      )
      nf = described_class.new(cfg_no_progress, diagnostics: diagnostics, on_result: nil)
      nf.start(2)
      nf.notify(killed, 1)
      expect($stderr.string).to eq("")
    end

    it "does not build a progress bar when quiet is enabled" do
      cfg_quiet = Evilution::Config.new(
        baseline: false, skip_config_file: true, progress: true, format: :text, quiet: true
      )
      nf = described_class.new(cfg_quiet, diagnostics: diagnostics, on_result: nil)
      nf.start(2)
      nf.notify(killed, 1)
      expect($stderr.string).to eq("")
    end

    it "does not build a progress bar when verbose is enabled" do
      cfg_verbose = Evilution::Config.new(
        baseline: false, skip_config_file: true, progress: true, format: :text, verbose: true
      )
      nf = described_class.new(cfg_verbose, diagnostics: diagnostics, on_result: nil)
      nf.start(2)
      nf.notify(killed, 1)
      expect($stderr.string).to eq("")
    end

    it "does not build a progress bar when format is not text" do
      cfg_json = Evilution::Config.new(
        baseline: false, skip_config_file: true, progress: true, format: :json
      )
      nf = described_class.new(cfg_json, diagnostics: diagnostics, on_result: nil)
      nf.start(2)
      nf.notify(killed, 1)
      expect($stderr.string).to eq("")
    end
  end

  it "does not build a progress bar when stderr is not a tty" do
    non_tty = StringIO.new
    original = $stderr
    $stderr = non_tty
    progress_cfg = Evilution::Config.new(
      baseline: false, skip_config_file: true, progress: true, format: :text
    )
    nf = described_class.new(progress_cfg, diagnostics: diagnostics, on_result: nil)
    nf.start(2)
    nf.notify(killed, 1)
    expect(non_tty.string).to eq("")
  ensure
    $stderr = original
  end
end
