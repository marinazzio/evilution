# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real, in a process of its own, against a concern whose
# `prepended` block declares a scope, a callback block, a validation with a
# condition and an AASM event with a guard.
#
# Each of the four has a branch the specs exercise and one they never reach.
# The fixture has a spec file for a class that prepended the concern before
# the run and one for a class that prepends it inside an example, run apart:
# either would kill the mutations the other is there to show. Both pin the
# rest of the block to a single run -- one callback step, one error, one
# machine -- so a re-declaration that ran more than the mutated declaration
# on a loaded class would kill the mutations of the untested branches too.
RSpec.describe "Declarations in a concern's prepended block", :aggregate_failures do
  project = File.expand_path("../../support/fixtures/prepended_declarations_project", __dir__)
  root = File.expand_path("../../..", __dir__)
  # subject name => [untested branch line, tested branch line]
  branches = {
    "Audited.visible" => [17, 19],
    "Audited.before_validation" => [25, 27],
    "Audited.validate(:credit_limit)" => [33, 35],
    "Audited#ship" => [44, 46]
  }
  # `filter`, `select!` on a fresh array and `fetch` of a key every row has
  # answer like `select` and `[]`; `paid.equal?(true)` and a bare `paid` like
  # `paid == true` for the booleans the specs pass. Nothing else on a tested
  # line may get through.
  equivalent_operators = %w[bang_method index_to_fetch send_mutation equality_to_identity method_call_removal]

  run_evilution = lambda do |isolation, spec|
    Dir.mktmpdir("prepended_declarations") do |dir|
      FileUtils.cp_r(File.join(project, "."), dir)
      # The fixture's specs are kept under other names so this suite does not
      # load them as its own.
      FileUtils.mv(File.join(dir, "spec/#{spec}_spec.rb.fixture"), File.join(dir, "spec/#{spec}_spec.rb"))
      command = [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run",
                 "lib/audited.rb", "--spec", "spec/#{spec}_spec.rb", "--preload", "spec/spec_helper.rb",
                 "--isolation", isolation, "--format", "json"]
      out, err, status = Open3.capture3(*command, chdir: dir)
      raise "evilution failed (#{status.exitstatus}): #{err}" if out.strip.empty?

      report = JSON.parse(out)
      raise "evilution failed (#{status.exitstatus}): #{report["error"]}" if report.key?("error")

      report
    end
  end

  # One evilution run per isolation and spec file, made when an example first
  # asks for it and shared by the others: each is a whole run in a process of
  # its own, and no example changes the report it reads.
  reports = Hash.new { |runs, key| runs[key] = run_evilution.call(*key) }

  def lines_of(report, bucket)
    report.fetch(bucket).map { |entry| entry.fetch("line") }
  end

  def operators_on(report, bucket, line)
    report.fetch(bucket).select { |entry| entry.fetch("line") == line }.map { |entry| entry.fetch("operator") }.uniq
  end

  %w[fork in_process].each do |isolation|
    { "loaded" => "a class that prepended the concern before the run",
      "late" => "a class that prepends the concern during the run" }.each do |spec, reader|
      context "under #{isolation} isolation, read through #{reader}" do
        let(:report) { reports[[isolation, spec]] }

        it "mutates each declaration as a subject named after the concern" do
          expect(report.fetch("subjects").map { |subject| subject.fetch("name") }).to include(*branches.keys)
          expect(report.dig("summary", "errors")).to eq(0)
          expect(report.dig("summary", "neutral")).to eq(0)
        end

        it "kills mutations of each tested branch and none of the untested ones" do
          branches.each_value do |untested, tested|
            expect(lines_of(report, "killed")).to include(tested)
            expect(lines_of(report, "killed")).not_to include(untested)
            expect(lines_of(report, "survived")).to include(untested)
          end
        end

        it "lets only equivalent mutations of the tested branches survive" do
          branches.each_value do |_untested, tested|
            expect(operators_on(report, "survived", tested) - equivalent_operators).to eq([])
          end
        end
      end
    end
  end
end
