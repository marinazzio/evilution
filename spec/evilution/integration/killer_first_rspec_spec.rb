# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real, in a process of its own, on a spec file whose first
# example is the cheap one and kills nothing, and whose second takes longer and
# kills every mutant of `state`. The first example logs to tmp/ran.log, each
# time it runs, whether it saw the original code or a mutant.
#
# The first mutant of `state` runs the cheap example first and is killed by
# the second; every later one is sent out with that killer, runs it first, and
# stops there.
RSpec.describe "Running the examples that killed first with RSpec", :aggregate_failures do
  project = File.expand_path("../../support/fixtures/stop_on_kill_project", __dir__)
  root = File.expand_path("../../..", __dir__)

  run_evilution = lambda do |flags|
    Dir.mktmpdir("killer_first") do |dir|
      FileUtils.cp_r(File.join(project, "."), dir)
      # The fixture's specs are kept under other names so this suite does not
      # load them as its own.
      file = File.join(dir, "spec/gate_spec.rb")
      FileUtils.mv("#{file}.killer_later", file)
      command = [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run", "lib/gate.rb",
                 "--format", "json", *flags]
      out, err, status = Open3.capture3(*command, chdir: dir)
      raise "evilution failed (#{status.exitstatus}): #{err}" if out.strip.empty?

      report = JSON.parse(out)
      raise "evilution failed (#{status.exitstatus}): #{report["error"]}" if report.key?("error")

      log = File.join(dir, "tmp/ran.log")
      { report: report, ran: File.exist?(log) ? File.readlines(log, chomp: true) : [] }
    end
  end

  runs = Hash.new { |cache, flags| cache[flags] = run_evilution.call(flags) }

  def state_entries(report)
    report.fetch("killed").select { |entry| (4..6).cover?(entry.fetch("line")) }
  end

  %w[fork in_process].each do |isolation|
    context "under #{isolation} isolation" do
      it "runs the cheap example on the first mutant only" do
        run = runs[["--isolation", isolation]]

        state = state_entries(run[:report])
        expect(state.length).to be > 2
        expect(run[:ran].count("mutant")).to eq(1)
        expect(state.map { |entry| entry.fetch("examples_run") }).to eq([2] + ([1] * (state.length - 1)))
        expect(state.map { |entry| entry.fetch("killing_test") }).to all(end_with("spec/gate_spec.rb[1:2]"))
      end

      it "runs the examples in the order they are defined with --no-stop-on-kill" do
        run = runs[["--isolation", isolation, "--no-stop-on-kill"]]

        state = state_entries(run[:report])
        expect(run[:ran].count("mutant")).to eq(state.length)
        expect(state.map { |entry| entry.fetch("examples_run") }).to all(eq(2))
      end

      it "reaches the same verdicts either way" do
        ordered = runs[["--isolation", isolation]][:report]
        defined = runs[["--isolation", isolation, "--no-stop-on-kill"]][:report]

        expect(ordered.fetch("summary").slice("killed", "survived"))
          .to eq(defined.fetch("summary").slice("killed", "survived"))
      end
    end
  end

  # The mutations already sent out when the first kill comes back go without
  # it; the rest are sent with it.
  it "hands the killer to the mutations a parallel run sends out after the kill" do
    run = runs[%w[--isolation fork --jobs 2]]

    state = state_entries(run[:report])
    expect(run[:ran].count("mutant")).to be_between(1, 2)
    expect(state.count { |entry| entry.fetch("examples_run") == 1 }).to be >= state.length - 2
  end
end
