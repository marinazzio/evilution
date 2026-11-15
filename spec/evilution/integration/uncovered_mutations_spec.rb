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

  # What SimpleCov does when a spec helper starts it: start line coverage
  # unless something already runs it.
  starts_coverage = lambda do |dir|
    helper = File.join(dir, "spec/spec_helper.rb")
    File.write(helper, "require \"coverage\"\nCoverage.start(lines: true) unless Coverage.running?\n#{File.read(helper)}")
  end

  # One evilution run per set of flags, shared by the examples that read it.
  runs = Hash.new { |cache, flags| cache[flags] = in_project.call { |dir| run_evilution.call(dir, flags) } }

  def lines_of(report, bucket)
    report.fetch(bucket).map { |entry| entry.fetch("line") }.uniq.sort
  end

  # The preload is counted only when the tests run in processes forked from
  # it, so the preloaded context forks.
  [[], ["--isolation", "fork", "--preload", "spec/spec_helper.rb"]].each do |flags|
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

  context "when the spec helper starts coverage itself" do
    [[], ["--isolation", "fork", "--preload", "lib/ledger.rb"]].each do |flags|
      it "runs the tests without errors and still reports the uncovered mutants (#{flags.join(" ")})" do
        report = in_project.call do |dir|
          starts_coverage.call(dir)
          run_evilution.call(dir, flags)
        end

        expect(report["summary"]["errors"]).to eq(0)
        expect(report["summary"].fetch("baseline_failures", [])).to eq([])
        expect(report["summary"]["killed"]).to be_positive
        expect(lines_of(report, "uncovered")).to eq(refund)
      end
    end
  end

  it "runs them all with --no-skip-uncovered" do
    report = runs[["--no-skip-uncovered"]]

    expect(report["uncovered"]).to eq([])
    expect(lines_of(report, "survived")).to include(refund_body)
  end

  # The coverage map is cached across runs. A file the specs load that starts
  # calling the code changes which lines run, though neither the target nor
  # its spec file changed: the cached map must not be read then.
  it "rebuilds the map when another file the specs load starts calling the code" do
    in_project.call do |dir|
      settlement = File.join(dir, "lib/settlement.rb")
      write_settlement = lambda do |body, expected|
        File.write(settlement, "module Settlement\n  EXPECTED = #{expected}\n\n  " \
                               "def self.settle(ledger)\n    #{body}\n  end\nend\n")
      end
      write_settlement.call("ledger", 10)
      spec = File.join(dir, "spec/ledger_spec.rb")
      File.write(spec, File.read(spec).sub(/^end\s*\z/, <<~RUBY))
          it "settles" do
            ledger = described_class.new
            ledger.add(10)
            Settlement.settle(ledger)
            expect(ledger.total).to eq(Settlement::EXPECTED)
          end
        end
      RUBY
      File.write(spec, File.read(spec).sub("require_relative \"spec_helper\"\n", "\\0require \"settlement\"\n"))

      first = run_evilution.call(dir, [])
      write_settlement.call("ledger.refund(1)", 8)
      second = run_evilution.call(dir, [])

      expect(lines_of(first, "uncovered")).to eq(refund)
      expect(lines_of(second, "uncovered")).to eq([])
      expect(second["summary"]["killed"]).to be > first["summary"]["killed"]
    end
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
