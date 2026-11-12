# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real, in a process of its own, on mutants that fail the
# first example and then hang in the next. A run that stops at the kill never
# reaches the hang, so the mutant is killed rather than timed out -- the one
# status change stopping is allowed to make.
RSpec.describe "Stopping a kill check before a later example hangs", :aggregate_failures do
  project = File.expand_path("../../support/fixtures/stop_on_kill_project", __dir__)
  root = File.expand_path("../../..", __dir__)

  # The fixture has a handful of mutants; with --no-stop-on-kill each one waits
  # out the timeout, so forked children run side by side to keep this short.
  jobs = { "fork" => %w[--jobs 4], "in_process" => [] }

  run_evilution = lambda do |isolation, flags|
    Dir.mktmpdir("stop_on_kill_timeout") do |dir|
      FileUtils.cp_r(File.join(project, "."), dir)
      # The fixture's specs are kept under other names so this suite does not
      # load them as its own.
      file = File.join(dir, "spec/gate_spec.rb")
      FileUtils.mv("#{file}.slow", file)
      command = [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run", "lib/gate.rb",
                 "--isolation", isolation, "--format", "json", "--timeout", "2", *jobs.fetch(isolation), *flags]
      out, err, status = Open3.capture3(*command, chdir: dir)
      raise "evilution failed (#{status.exitstatus}): #{err}" if out.strip.empty?

      report = JSON.parse(out)
      raise "evilution failed (#{status.exitstatus}): #{report["error"]}" if report.key?("error")

      report
    end
  end

  # The mutants of `state`, which the examples check; those of `label`, which
  # none does, survive either way.
  def state_mutants(report, bucket)
    report.fetch(bucket).count { |entry| (4..6).cover?(entry.fetch("line")) }
  end

  %w[fork in_process].each do |isolation|
    context "under #{isolation} isolation" do
      it "reports the mutants killed" do
        report = run_evilution.call(isolation, [])

        expect(state_mutants(report, "killed")).to be_positive
        expect(state_mutants(report, "timed_out")).to eq(0)
      end

      it "reports them timed out with --no-stop-on-kill" do
        report = run_evilution.call(isolation, ["--no-stop-on-kill"])

        expect(state_mutants(report, "timed_out")).to be_positive
        expect(state_mutants(report, "killed")).to eq(0)
      end
    end
  end
end
