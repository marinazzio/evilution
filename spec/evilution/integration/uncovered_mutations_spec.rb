# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real, in a process of its own, with coverage targeting on a
# class whose `refund` no example calls. Its body never runs, so its mutants are
# reported uncovered without a run; a mutation that changes a line that runs
# only while the file loads (the constant, `attr_reader`, a `def` line) runs.
RSpec.describe "Mutations on lines no test executes", :aggregate_failures do
  project = File.expand_path("../../support/fixtures/uncovered_project", __dir__)
  root = File.expand_path("../../..", __dir__)
  # A mutation that replaces the whole body is reported at the `def` line,
  # which ran while the file loaded; it changes only the body.
  refund = [16, 17]
  refund_body = 17
  limit = 4

  run_evilution = lambda do |dir, flags|
    command = [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run", "lib/ledger.rb",
               "--example-targeting", "coverage", "--format", "json", "--no-progress", *flags]
    out, err, status = Open3.capture3(*command, chdir: dir)
    raise "evilution failed (#{status.exitstatus}): #{err}" if out.strip.empty?

    report = JSON.parse(out)
    raise "evilution failed (#{status.exitstatus}): #{report["error"]}" if report.key?("error")

    report
  end

  in_project = lambda do |&block|
    Dir.mktmpdir("uncovered") do |dir|
      FileUtils.cp_r(File.join(project, "."), dir)
      # Kept under another name so this suite does not load it as its own.
      FileUtils.mv(File.join(dir, "spec/ledger_spec.rb.fixture"), File.join(dir, "spec/ledger_spec.rb"))
      block.call(dir)
    end
  end

  # One evilution run per set of flags, shared by the examples that read it.
  runs = Hash.new { |cache, flags| cache[flags] = in_project.call { |dir| run_evilution.call(dir, flags) } }

  def lines_of(report, bucket)
    report.fetch(bucket).map { |entry| entry.fetch("line") }.uniq.sort
  end

  [[], ["--preload", "spec/spec_helper.rb"]].each do |flags|
    context(flags.empty? ? "when the spec file loads the code" : "when the code is preloaded") do
      it "reports the mutants of a method no example calls as uncovered" do
        report = runs[flags]

        expect(lines_of(report, "uncovered")).to eq(refund)
        expect(report["summary"]["uncovered"]).to eq(report["uncovered"].length)
        expect(report["uncovered"].map { |entry| entry["status"] }.uniq).to eq(["uncovered"])
        expect(lines_of(report, "survived") & refund).to eq([])
      end

      it "runs the mutants of a line that ran only while the file loaded" do
        report = runs[flags]

        expect(lines_of(report, "survived")).to include(limit)
        expect(lines_of(report, "uncovered")).not_to include(limit)
      end

      it "scores the uncovered mutants as survivors" do
        summary = runs[flags]["summary"]
        denominator = summary["killed"] + summary["survived"] + summary["timed_out"] + summary["uncovered"]

        expect(summary["score"]).to eq((summary["killed"].to_f / denominator).round(4))
      end
    end
  end

  it "runs them all with --no-skip-uncovered" do
    report = runs[["--no-skip-uncovered"]]

    expect(report["uncovered"]).to eq([])
    expect(lines_of(report, "survived")).to include(refund_body)
  end

  it "reports them uncovered again on an incremental re-run" do
    in_project.call do |dir|
      first = run_evilution.call(dir, ["--incremental"])
      second = run_evilution.call(dir, ["--incremental"])

      expect(lines_of(second, "uncovered")).to eq(refund)
      expect(second["summary"]).to include(first["summary"].slice("killed", "survived", "uncovered", "score"))
    end
  end
end
