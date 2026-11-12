# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real, in a process of its own, with the Minitest
# integration, and watches which tests each mutation's run got to: the tests
# after the first one log to tmp/ran.log whether they saw the original code or
# a mutant.
RSpec.describe "Stopping a kill check at its first kill with Minitest", :aggregate_failures do
  project = File.expand_path("../../support/fixtures/stop_on_kill_project", __dir__)
  root = File.expand_path("../../..", __dir__)

  run_evilution = lambda do |variant, isolation, flags|
    Dir.mktmpdir("stop_on_kill_minitest") do |dir|
      FileUtils.cp_r(File.join(project, "."), dir)
      # The fixture's tests are kept under other names so this suite does not
      # load them as its own.
      file = File.join(dir, "test/gate_test.rb")
      FileUtils.mv("#{file}.minitest.#{variant}", file)
      command = [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run", "lib/gate.rb",
                 "--integration", "minitest", "--isolation", isolation, "--format", "json", *flags]
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
  # tests check; `label` is checked by none, and its mutants run after those of
  # `state`, so they survive only if a run that stopped at its kill left the
  # next one free to run its tests.
  def subjects_of(report, bucket)
    methods = { (4..6) => "state", (10..12) => "label" }
    report.fetch(bucket).map { |entry| methods.find { |lines, _| lines.cover?(entry.fetch("line")) }.last }.uniq.sort
  end

  # The mutants of `state` in a bucket of the report.
  def state_mutants(report, bucket)
    report.fetch(bucket).count { |entry| (4..6).cover?(entry.fetch("line")) }
  end

  # The mutants of `state` in every bucket of the report, whatever their status.
  def all_state_mutants(report)
    %w[killed survived neutral equivalent unresolved unparseable timed_out errors].sum do |bucket|
      state_mutants(report, bucket)
    end
  end

  %w[fork in_process].each do |isolation|
    context "under #{isolation} isolation" do
      context "when the first test kills every mutant" do
        it "runs no test after the kill" do
          run = runs[["kill", isolation, []]]

          expect(subjects_of(run[:report], "killed")).to eq(["state"])
          expect(run[:ran]).not_to include("mutant")
          # The baseline still ran every test.
          expect(run[:ran].first(2)).to eq(%w[original original])
        end

        it "runs every test for the mutations that follow" do
          run = runs[["kill", isolation, []]]

          expect(subjects_of(run[:report], "survived")).to eq(["label"])
        end

        it "runs every test with --no-stop-on-kill" do
          run = runs[["kill", isolation, ["--no-stop-on-kill"]]]

          expect(subjects_of(run[:report], "killed")).to eq(["state"])
          expect(run[:ran]).to include("mutant")
        end
      end

      # A failure the baseline already saw says nothing about the mutant, so
      # the run goes on to the test that does.
      context "when a test the baseline saw failing comes first" do
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
      # the verdict, so every test runs and the mutant ends neutral. That
      # failure is there on the mutants of `label` too, so they are neutral as
      # well.
      context "when the only failing test is one the baseline saw failing" do
        it "runs every test, and leaves the mutants neutral" do
          run = runs[["known_only", isolation, []]]

          expect(subjects_of(run[:report], "neutral")).to eq(%w[label state])
          expect(subjects_of(run[:report], "killed")).to eq([])
          # Every mutant of `state` is neutral, and both tests after the failing
          # one ran on each of them.
          state = all_state_mutants(run[:report])
          expect(state_mutants(run[:report], "neutral")).to eq(state)
          expect(run[:ran].count("mutant")).to eq(2 * state)
          expect(run[:ran]).to include("mutant")
        end
      end

      # With nothing but infrastructure crashes no failure decides the
      # verdict, so every test runs and the mutant ends neutral.
      context "when the only failure is an infrastructure crash" do
        it "runs every test, and leaves the mutants neutral" do
          run = runs[["infra_only", isolation, []]]

          expect(subjects_of(run[:report], "neutral")).to eq(["state"])
          expect(subjects_of(run[:report], "killed")).to eq([])
          # The crash needs a mutant of `state`, so the mutants of `label`,
          # which no test checks, survive.
          expect(subjects_of(run[:report], "survived")).to eq(["label"])
          # Every mutant of `state` is neutral, and both tests after the crashing
          # one ran on each of them.
          state = all_state_mutants(run[:report])
          expect(state_mutants(run[:report], "neutral")).to eq(state)
          expect(run[:ran].count("mutant")).to eq(2 * state)
          expect(run[:ran]).to include("mutant")
        end
      end

      # A run that stops at the kill never reaches the hang after it, so the
      # mutant is killed rather than timed out -- the one status change
      # stopping is allowed to make. With --no-stop-on-kill each mutant waits
      # out the timeout, so forked children run side by side to keep this
      # short.
      context "when a test after the kill hangs" do
        jobs = isolation == "fork" ? %w[--jobs 4] : []

        it "reports the mutants killed" do
          report = runs[["slow", isolation, ["--timeout", "2", *jobs]]][:report]

          expect(state_mutants(report, "killed")).to be_positive
          expect(state_mutants(report, "timed_out")).to eq(0)
        end

        it "reports them timed out with --no-stop-on-kill" do
          report = runs[["slow", isolation, ["--timeout", "2", *jobs, "--no-stop-on-kill"]]][:report]

          expect(state_mutants(report, "timed_out")).to be_positive
          expect(state_mutants(report, "killed")).to eq(0)
        end
      end
    end
  end
end
