# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real, in a process of its own, and watches which examples
# each mutation's run got to: the examples after the first one log to
# tmp/ran.log whether they saw the original code or a mutant.
RSpec.describe "Stopping a kill check at its first kill with RSpec", :aggregate_failures do
  project = File.expand_path("../../support/fixtures/stop_on_kill_project", __dir__)
  root = File.expand_path("../../..", __dir__)

  run_evilution = lambda do |variant, isolation, flags|
    Dir.mktmpdir("stop_on_kill") do |dir|
      FileUtils.cp_r(File.join(project, "."), dir)
      # The fixture's specs are kept under other names so this suite does not
      # load them as its own.
      file = File.join(dir, "spec/gate_spec.rb")
      FileUtils.mv("#{file}.#{variant}", file)
      command = [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run", "lib/gate.rb",
                 "--isolation", isolation, "--format", "json", *flags]
      out, err, status = Open3.capture3(*command, chdir: dir)
      raise "evilution failed (#{status.exitstatus}): #{err}" if out.strip.empty?

      report = JSON.parse(out)
      raise "evilution failed (#{status.exitstatus}): #{report["error"]}" if report.key?("error")

      log = File.join(dir, "tmp/ran.log")
      { report: report, ran: File.exist?(log) ? File.readlines(log, chomp: true) : [] }
    end
  end

  # One evilution run per variant, isolation and flags, made when an example
  # first asks for it and shared by the others.
  runs = Hash.new { |cache, key| cache[key] = run_evilution.call(*key) }

  # Which methods have mutants in a bucket of the report. `state` is what the
  # examples check; `label` is checked by none, and its mutants run after
  # those of `state`, so they survive only if a run that stopped at its kill
  # left the next one free to run its examples.
  def subjects_of(report, bucket)
    methods = { (4..6) => "state", (10..12) => "label" }
    report.fetch(bucket).map { |entry| methods.find { |lines, _| lines.cover?(entry.fetch("line")) }.last }.uniq.sort
  end

  # The mutants of `state` in a bucket of the report.
  def state_mutants(report, bucket)
    report.fetch(bucket).count { |entry| (4..6).cover?(entry.fetch("line")) }
  end

  %w[fork in_process].each do |isolation|
    context "under #{isolation} isolation" do
      context "when the first example kills every mutant" do
        it "runs no example after the kill" do
          run = runs[["kill", isolation, []]]

          expect(subjects_of(run[:report], "killed")).to eq(["state"])
          expect(run[:ran]).not_to include("mutant")
          # The baseline still ran every example.
          expect(run[:ran].first(2)).to eq(%w[original original])
        end

        it "runs every example for the mutations that follow" do
          run = runs[["kill", isolation, []]]

          expect(subjects_of(run[:report], "survived")).to eq(["label"])
        end

        it "runs every example with --no-stop-on-kill" do
          run = runs[["kill", isolation, ["--no-stop-on-kill"]]]

          expect(subjects_of(run[:report], "killed")).to eq(["state"])
          expect(run[:ran]).to include("mutant")
        end
      end

      # A failure the baseline already saw says nothing about the mutant, so
      # the run goes on to the example that does.
      context "when an example the baseline saw failing comes first" do
        it "goes on to the kill, and stops there" do
          run = runs[["known", isolation, []]]

          expect(subjects_of(run[:report], "killed")).to eq(["state"])
          expect(run[:ran]).not_to include("mutant")
          # The baseline went on past its own failure.
          expect(run[:ran]).to include("original")
        end
      end

      # An infrastructure crash alone would leave the mutant neutral, so the
      # run goes on to find out whether a real failure follows.
      context "when an infrastructure crash comes first" do
        it "goes on to the kill, and stops there" do
          run = runs[["infra", isolation, []]]

          expect(subjects_of(run[:report], "killed")).to eq(["state"])
          expect(subjects_of(run[:report], "neutral")).to eq([])
          expect(run[:ran]).not_to include("mutant")
        end
      end

      # With nothing but failures the baseline already saw, no failure decides
      # the verdict, so every example runs and the mutant ends neutral. That
      # failure is there on the mutants of `label` too, so they are neutral as
      # well.
      #
      # Example targeting would run a mutant's examples a second time, the whole
      # file this time, after a first run with nothing but known failures, so
      # it is turned off to leave one run per mutant to count.
      context "when the only failing example is one the baseline saw failing" do
        it "runs every example, and leaves the mutants neutral" do
          run = runs[["known_only", isolation, ["--no-example-targeting"]]]

          expect(subjects_of(run[:report], "neutral")).to eq(%w[label state])
          expect(subjects_of(run[:report], "killed")).to eq([])
          # Both examples after the failing one ran on every mutant of `state`.
          expect(run[:ran].count("mutant")).to eq(2 * state_mutants(run[:report], "neutral"))
          expect(run[:ran]).to include("mutant")
        end
      end

      # With nothing but infrastructure crashes no failure decides the
      # verdict, so every example runs and the mutant ends neutral.
      context "when the only failure is an infrastructure crash" do
        it "runs every example, and leaves the mutants neutral" do
          run = runs[["infra_only", isolation, []]]

          expect(subjects_of(run[:report], "neutral")).to eq(["state"])
          expect(subjects_of(run[:report], "killed")).to eq([])
          # Both examples after the crashing one ran on every mutant of `state`.
          expect(run[:ran].count("mutant")).to eq(2 * state_mutants(run[:report], "neutral"))
          expect(run[:ran]).to include("mutant")
        end
      end
    end
  end
end
