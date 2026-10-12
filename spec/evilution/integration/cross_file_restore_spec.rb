# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real over two files, the second of which reads a method
# and a constant of the first, in a process of its own.
#
# Nothing in the first file's spec looks at that method or constant, so all
# their mutations survive -- and the last of them must not stay applied while
# the second file is mutated. `Checker.unused` is the witness: no example
# calls it, so its mutations survive unless the examples fail for a reason of
# their own, such as a limit left mutated by the file before.
RSpec.describe "Restoring a file after its mutations", :aggregate_failures do
  project = File.expand_path("../../support/fixtures/cross_file_project", __dir__)
  root = File.expand_path("../../..", __dir__)

  # The fixture's specs are kept under another name so this suite does not
  # load them as its own.
  copy_project = lambda do |dir|
    FileUtils.cp_r(File.join(project, "."), dir)
    %w[limits checker].each do |name|
      FileUtils.mv(File.join(dir, "spec/#{name}_spec.rb.fixture"), File.join(dir, "spec/#{name}_spec.rb"))
    end
  end

  run_evilution = lambda do |isolation|
    Dir.mktmpdir("cross_file_restore") do |dir|
      copy_project.call(dir)
      command = [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run",
                 "lib/limits.rb", "lib/checker.rb", "--preload", "spec/spec_helper.rb",
                 "--isolation", isolation, "--format", "json"]
      out, err, status = Open3.capture3(*command, chdir: dir)
      raise "evilution failed (#{status.exitstatus}): #{err}" if out.strip.empty?

      report = JSON.parse(out)
      raise "evilution failed (#{status.exitstatus}): #{report["error"]}" if report.key?("error")

      report
    end
  end

  # One run per isolation, shared by the examples: each is a whole evilution
  # run in a process of its own.
  before(:context) do
    @reports = %w[fork in_process].to_h { |isolation| [isolation, run_evilution.call(isolation)] }
  end

  def subject_of(report, name)
    subjects = report.fetch("subjects")
    found = subjects.find { |subject| subject.fetch("name") == name }
    return found if found

    raise "no subject #{name.inspect} in the report, which has #{subjects.map { |subject| subject.fetch("name") }.inspect}"
  end

  %w[fork in_process].each do |isolation|
    context "under #{isolation} isolation" do
      let(:report) { @reports.fetch(isolation) }

      it "runs without errors" do
        expect(report.dig("summary", "errors")).to eq(0)
        expect(report.dig("summary", "neutral")).to eq(0)
      end

      it "leaves the first file's untested method and constant alive" do
        expect(subject_of(report, "Limits.step").fetch("killed")).to eq(0)
        expect(subject_of(report, "Limits::MAX").fetch("killed")).to eq(0)
      end

      it "kills nothing in the second file through a mutation left over from the first" do
        unused = subject_of(report, "Checker.unused")

        expect(unused.fetch("total")).to be_positive
        expect(unused.fetch("killed")).to eq(0)
      end

      it "still kills the second file's own mutations" do
        expect(subject_of(report, "Checker.within?").fetch("killed")).to be_positive
      end
    end
  end

  it "scores the second file the same under both isolations" do
    scores = @reports.values.map { |report| subject_of(report, "Checker.within?").slice("killed", "survived") }

    expect(scores.first).to eq(scores.last)
  end
end
