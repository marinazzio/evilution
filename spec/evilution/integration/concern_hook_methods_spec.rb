# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real, in a process of its own, against two concerns whose
# hook blocks define methods: one in `included do ... end`, one in
# `prepended do ... end`.
#
# A block runs when a class takes the concern, so a class loaded before the
# run has the methods of the original block and has to be given the mutated
# one. The fixture has a spec file for such a class and one for a class that
# takes the concerns inside an example, run apart: either would kill the
# mutations the other is there to show. The first also pins the other
# declaration of each block to a single run. Each block defines a method no
# example calls as well: its mutations survive unless the rest of the block is
# run on a loaded class a second time, which fails every example.
#
# The loaded class also defines `kind` over the one the included block gives
# it. The block's is dead code for that class, and running it again must not
# put it back in the place of the class's own.
RSpec.describe "Methods defined in a concern's hook blocks", :aggregate_failures do
  project = File.expand_path("../../support/fixtures/hook_method_project", __dir__)
  root = File.expand_path("../../..", __dir__)

  run_evilution = lambda do |isolation, spec|
    Dir.mktmpdir("concern_hook_methods") do |dir|
      FileUtils.cp_r(File.join(project, "."), dir)
      # The fixture's specs are kept under other names so this suite does not
      # load them as its own.
      FileUtils.mv(File.join(dir, "spec/#{spec}_spec.rb.fixture"), File.join(dir, "spec/#{spec}_spec.rb"))
      command = [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run",
                 "lib/tracked.rb", "lib/stamped.rb", "--spec", "spec/#{spec}_spec.rb", "--preload", "spec/spec_helper.rb",
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

  def subject_of(report, name)
    subjects = report.fetch("subjects")
    found = subjects.find { |subject| subject.fetch("name") == name }
    return found if found

    raise "no subject #{name.inspect} in the report, which has #{subjects.map { |subject| subject.fetch("name") }.inspect}"
  end

  %w[fork in_process].each do |isolation|
    it "leaves a loaded class the method it defined over the block's, under #{isolation} isolation" do
      overridden = subject_of(reports[[isolation, "loaded"]], "Tracked#kind")

      expect(overridden.fetch("total")).to be_positive
      expect(overridden.fetch("killed")).to eq(0)
      expect(subject_of(reports[[isolation, "late"]], "Tracked#kind").fetch("survived")).to eq(0)
    end

    { "loaded" => "a class that took the concerns before the run",
      "late" => "a class that takes the concerns during the run" }.each do |spec, reader|
      context "under #{isolation} isolation, read through #{reader}" do
        let(:report) { reports[[isolation, spec]] }

        it "runs without errors" do
          expect(report.dig("summary", "errors")).to eq(0)
          expect(report.dig("summary", "neutral")).to eq(0)
        end

        it "kills the mutations of the methods an included block defines" do
          expect(subject_of(report, "Tracked.level").fetch("killed")).to be >= 7
          expect(subject_of(report, "Tracked#label").fetch("survived")).to eq(0)
        end

        it "kills the mutations of the method a prepended block defines" do
          expect(subject_of(report, "Stamped.stamp").fetch("killed")).to be >= 9
        end

        it "kills nothing in the methods no example calls" do
          %w[Tracked.unused Stamped.unstamped].each do |name|
            unused = subject_of(report, name)

            expect(unused.fetch("total")).to be_positive
            expect(unused.fetch("killed")).to eq(0)
          end
        end
      end
    end
  end
end
