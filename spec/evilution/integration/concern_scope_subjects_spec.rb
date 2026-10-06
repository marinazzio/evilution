# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real against an ActiveSupport::Concern whose `included`
# block declares a scope, in a process of its own: the concern has to be
# loaded, mutated and re-declared the way a user's would be.
#
# The scope has a branch the specs exercise (a visitor) and one they never
# reach (an admin). One spec reads it through a class loaded before the run,
# one through a class that includes the concern only inside the example, and
# one pins the block's other declaration to a single run: a mutation that
# reached neither class would survive on the tested branch, and re-running
# the whole block on a loaded class would fail every mutation.
RSpec.describe "Concern scope subjects", :aggregate_failures do
  let(:project) { File.expand_path("../../support/fixtures/concern_project", __dir__) }
  let(:root) { File.expand_path("../../..", __dir__) }
  let(:condition_line) { 14 }
  let(:untested_branch_line) { 15 }
  let(:tested_branch_line) { 17 }
  let(:equivalent_operators) { %w[bang_method index_to_fetch send_mutation] }

  # The fixture's spec is kept under another name so this suite does not load
  # it as one of its own.
  def copy_project(dir)
    FileUtils.cp_r(File.join(project, "."), dir)
    FileUtils.mv(File.join(dir, "spec/publishable_spec.rb.fixture"), File.join(dir, "spec/publishable_spec.rb"))
  end

  def command(isolation)
    [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run", "lib/publishable.rb",
     "--preload", "spec/spec_helper.rb", "--isolation", isolation, "--format", "json"]
  end

  def run_evilution(isolation)
    Dir.mktmpdir("concern_scope_subjects") do |dir|
      copy_project(dir)
      out, err, status = Open3.capture3(*command(isolation), chdir: dir)
      raise "evilution failed (#{status.exitstatus}): #{err}" if out.strip.empty?

      report = JSON.parse(out)
      raise "evilution failed (#{status.exitstatus}): #{report["error"]}" if report.key?("error")

      report
    end
  end

  def lines_of(report, bucket)
    report.fetch(bucket).map { |entry| entry.fetch("line") }
  end

  def operators_on(report, bucket, line)
    report.fetch(bucket).select { |entry| entry.fetch("line") == line }.map { |entry| entry.fetch("operator") }.uniq
  end

  %w[fork in_process].each do |isolation|
    context "under #{isolation} isolation" do
      let(:report) { run_evilution(isolation) }

      it "mutates the scope as a subject named after the concern" do
        expect(report.fetch("subjects").map { |subject| subject.fetch("name") }).to eq(["Publishable.visible"])
        expect(report.dig("summary", "errors")).to eq(0)
        expect(report.dig("summary", "neutral")).to eq(0)
      end

      it "kills the mutations of the tested branch and none of the untested one" do
        expect(operators_on(report, "killed", tested_branch_line)).to include("collection_replacement", "block_removal")
        expect(lines_of(report, "killed")).not_to include(untested_branch_line)
        expect(operators_on(report, "survived", untested_branch_line)).to include("collection_replacement")
      end

      # `select!` on a fresh array, `filter` and `fetch` of a key every row has
      # behave like the original; nothing else on that line may get through.
      it "lets only equivalent mutations of the tested branch survive" do
        expect(operators_on(report, "survived", tested_branch_line) - equivalent_operators).to eq([])
        expect(lines_of(report, "survived") - [tested_branch_line, untested_branch_line, condition_line]).to eq([])
      end
    end
  end
end
