# frozen_string_literal: true

require "stringio"
require "evilution/config"
require "evilution/runner/diagnostics"

RSpec.describe Evilution::Runner::Diagnostics do
  def config(**overrides)
    Evilution::Config.new(baseline: false, skip_config_file: true, **overrides)
  end

  def tty_stderr
    io = StringIO.new
    allow(io).to receive(:tty?).and_return(true)
    io
  end

  describe "#log_memory" do
    it "writes a memory line when verbose and not quiet" do
      io = tty_stderr
      diag = described_class.new(config(verbose: true), stderr: io)
      allow(Evilution::Memory).to receive(:rss_mb).and_return(42.0)
      diag.log_memory("phase")
      expect(io.string).to include("[memory] phase:")
      expect(io.string).to include("42.0 MB")
    end

    it "is a no-op when not verbose" do
      io = tty_stderr
      diag = described_class.new(config(verbose: false), stderr: io)
      diag.log_memory("phase")
      expect(io.string).to eq("")
    end

    it "is a no-op when quiet" do
      io = tty_stderr
      diag = described_class.new(config(verbose: true, quiet: true), stderr: io)
      diag.log_memory("phase")
      expect(io.string).to eq("")
    end

    it "is a no-op when rss_mb is nil" do
      io = tty_stderr
      diag = described_class.new(config(verbose: true), stderr: io)
      allow(Evilution::Memory).to receive(:rss_mb).and_return(nil)
      diag.log_memory("phase")
      expect(io.string).to eq("")
    end

    it "includes context string when provided" do
      io = tty_stderr
      diag = described_class.new(config(verbose: true), stderr: io)
      allow(Evilution::Memory).to receive(:rss_mb).and_return(10.0)
      diag.log_memory("phase", "5 subjects")
      expect(io.string).to include("5 subjects")
    end
  end

  describe "#log_progress" do
    it "writes a progress line to stderr when on a tty" do
      io = tty_stderr
      diag = described_class.new(config, stderr: io)
      diag.log_progress(3, :killed)
      expect(io.string).to eq("mutation 3 killed\n")
    end

    it "is a no-op when not a tty" do
      io = StringIO.new
      allow(io).to receive(:tty?).and_return(false)
      diag = described_class.new(config, stderr: io)
      diag.log_progress(1, :killed)
      expect(io.string).to eq("")
    end

    it "is a no-op when quiet" do
      io = tty_stderr
      diag = described_class.new(config(quiet: true), stderr: io)
      diag.log_progress(1, :killed)
      expect(io.string).to eq("")
    end
  end

  describe "#log_mutation_diagnostics" do
    let(:result) do
      double(
        "Result",
        mutation: "Foo#bar",
        child_rss_kb: 2048,
        memory_delta_kb: 512,
        error?: false,
        error_class: nil,
        error_message: nil,
        error_backtrace: nil
      )
    end

    it "writes child_rss and delta information when verbose" do
      io = tty_stderr
      diag = described_class.new(config(verbose: true), stderr: io)
      diag.log_mutation_diagnostics(result)
      expect(io.string).to include("[verbose] Foo#bar")
      expect(io.string).to include("child_rss:")
      expect(io.string).to include("delta: +0.5 MB")
    end

    it "is a no-op when not verbose" do
      io = tty_stderr
      diag = described_class.new(config(verbose: false), stderr: io)
      diag.log_mutation_diagnostics(result)
      expect(io.string).to eq("")
    end

    it "logs error lines when result has an error" do
      err_result = double(
        "Result",
        mutation: "Foo#bar",
        child_rss_kb: nil,
        memory_delta_kb: nil,
        error?: true,
        error_class: "RuntimeError",
        error_message: "boom",
        error_backtrace: ["a.rb:1", "b.rb:2"]
      )
      io = tty_stderr
      diag = described_class.new(config(verbose: true), stderr: io)
      diag.log_mutation_diagnostics(err_result)
      expect(io.string).to include("error RuntimeError: boom")
      expect(io.string).to include("a.rb:1")
      expect(io.string).to include("b.rb:2")
    end
  end

  describe "#log_worker_stats" do
    it "is a no-op when stats empty" do
      io = tty_stderr
      diag = described_class.new(config(verbose: true), stderr: io)
      diag.log_worker_stats([])
      expect(io.string).to eq("")
    end

    it "writes a line per worker stat when verbose" do
      io = tty_stderr
      diag = described_class.new(config(verbose: true), stderr: io)
      stat = double("WorkerStat", pid: 123, items_completed: 5, utilization: 0.75)
      diag.log_worker_stats([stat])
      expect(io.string).to include("worker 123: 5 items")
      expect(io.string).to include("utilization 75.0%")
    end
  end

  describe "#aggregate_worker_stats" do
    it "returns stats unchanged when empty" do
      diag = described_class.new(config)
      expect(diag.aggregate_worker_stats([])).to eq([])
    end

    it "combines entries with the same pid" do
      stat_class = Evilution::Parallel::WorkQueue::WorkerStat
      a = stat_class.new(1, 2, 1.0, 2.0)
      b = stat_class.new(1, 3, 2.0, 3.0)
      diag = described_class.new(config)
      result = diag.aggregate_worker_stats([a, b])
      expect(result.length).to eq(1)
      expect(result.first.items_completed).to eq(5)
      expect(result.first.busy_time).to eq(3.0)
      expect(result.first.wall_time).to eq(5.0)
    end
  end
end
