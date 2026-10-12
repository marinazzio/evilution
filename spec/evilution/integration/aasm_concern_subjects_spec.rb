# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real, in a process of its own, against an AASM machine
# declared in a concern's `included` block.
#
# The event's guard has a branch the specs exercise (no `express`) and one
# they never reach. The specs read it through a class loaded before the run
# and one that includes the concern inside an example, pin the machine's own
# `after_all_transitions` callback to a single firing, and check the other
# states and events are still there: a re-declaration that missed either
# class, ran the whole machine again on a loaded one, or dropped the rest of
# it would fail mutations of the untested branch or spare those of the tested
# one.
RSpec.describe "AASM guard subjects in a concern", :aggregate_failures do
  project = File.expand_path("../../support/fixtures/aasm_concern_project", __dir__)
  root = File.expand_path("../../..", __dir__)
  let(:condition_line) { 20 }
  let(:untested_branch_line) { 21 }
  let(:tested_branch_line) { 23 }

  run_evilution = lambda do |isolation|
    Dir.mktmpdir("aasm_concern_subjects") do |dir|
      FileUtils.cp_r(File.join(project, "."), dir)
      # The fixture's spec is kept under another name so this suite does not
      # load it as one of its own.
      FileUtils.mv(File.join(dir, "spec/shippable_spec.rb.fixture"), File.join(dir, "spec/shippable_spec.rb"))
      command = [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run", "lib/shippable.rb",
                 "--preload", "spec/spec_helper.rb", "--isolation", isolation, "--format", "json"]
      out, err, status = Open3.capture3(*command, chdir: dir)
      raise "evilution failed (#{status.exitstatus}): #{err}" if out.strip.empty?

      report = JSON.parse(out)
      raise "evilution failed (#{status.exitstatus}): #{report["error"]}" if report.key?("error")

      report
    end
  end

  # One evilution run per isolation, made when an example first asks for it
  # and shared by the others: each is a whole run in a process of its own, and
  # no example changes the report it reads.
  reports = Hash.new { |runs, isolation| runs[isolation] = run_evilution.call(isolation) }

  def lines_of(report, bucket)
    report.fetch(bucket).map { |entry| entry.fetch("line") }
  end

  %w[fork in_process].each do |isolation|
    context "under #{isolation} isolation" do
      let(:report) { reports[isolation] }

      it "mutates the guard as a subject named after the concern" do
        expect(report.fetch("subjects").map { |subject| subject.fetch("name") }).to eq(["Shippable#ship"])
        expect(report.dig("summary", "errors")).to eq(0)
        expect(report.dig("summary", "neutral")).to eq(0)
      end

      it "kills every mutation of the tested branch and none of the untested one" do
        expect(lines_of(report, "killed")).to include(tested_branch_line)
        expect(lines_of(report, "killed")).not_to include(untested_branch_line)
        expect(lines_of(report, "survived")).to include(untested_branch_line)
        expect(lines_of(report, "survived") - [untested_branch_line, condition_line]).to eq([])
      end
    end
  end
end
