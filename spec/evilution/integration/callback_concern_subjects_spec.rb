# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real, in a process of its own, against callbacks and
# validations declared in a concern's `included` block.
#
# The concern has a callback block, a `validate` with an `if:` and a
# `validates` with an `unless:`, each with a branch the specs exercise (an
# ordinary record) and one they never reach (a rush one). The specs read
# every behaviour through a class loaded before the run and one that includes
# the concern inside an example, and pin callback order (also for a subclass
# with a callback of its own), single errors and single validators: a
# re-declaration that missed either class, moved a callback or left the
# original beside the mutant would fail mutations of the untested branch or
# spare those of the tested one.
RSpec.describe "Callback subjects in a concern", :aggregate_failures do
  let(:project) { File.expand_path("../../support/fixtures/callback_concern_project", __dir__) }
  let(:root) { File.expand_path("../../..", __dir__) }
  # subject name => [untested branch line, tested branch line]
  let(:branches) do
    {
      "Reviewable.before_validation" => [19, 21],
      "Reviewable.validate(:credit_limit)" => [28, 30],
      "Reviewable.validates(:title)" => [35, 37]
    }
  end
  # `paid.equal?(true)` and a bare `paid` answer like `paid == true` for the
  # booleans the specs pass; nothing else on a tested line may get through.
  let(:equivalent_operators) { %w[equality_to_identity method_call_removal] }

  # The fixture's spec is kept under another name so this suite does not load
  # it as one of its own.
  def copy_project(dir)
    FileUtils.cp_r(File.join(project, "."), dir)
    FileUtils.mv(File.join(dir, "spec/reviewable_spec.rb.fixture"), File.join(dir, "spec/reviewable_spec.rb"))
  end

  def command(isolation)
    [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run", "lib/reviewable.rb",
     "--preload", "spec/spec_helper.rb", "--isolation", isolation, "--format", "json"]
  end

  def run_evilution(isolation)
    Dir.mktmpdir("callback_concern_subjects") do |dir|
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

      it "kills mutations of each tested branch and none of the untested ones" do
        names = report.fetch("subjects").map { |subject| subject.fetch("name") }
        expect(names).to include(*branches.keys)
        expect(report.dig("summary", "errors")).to eq(0)
        expect(report.dig("summary", "neutral")).to eq(0)

        branches.each_value do |untested, tested|
          expect(lines_of(report, "killed")).to include(tested)
          expect(lines_of(report, "killed")).not_to include(untested)
          expect(lines_of(report, "survived")).to include(untested)
          expect(operators_on(report, "survived", tested) - equivalent_operators).to eq([])
        end
      end
    end
  end
end
