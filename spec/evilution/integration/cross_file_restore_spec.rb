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
  let(:project) { File.expand_path("../../support/fixtures/cross_file_project", __dir__) }
  let(:root) { File.expand_path("../../..", __dir__) }

  # The fixture's specs are kept under another name so this suite does not
  # load them as its own.
  def copy_project(dir)
    FileUtils.cp_r(File.join(project, "."), dir)
    %w[limits checker].each do |name|
      FileUtils.mv(File.join(dir, "spec/#{name}_spec.rb.fixture"), File.join(dir, "spec/#{name}_spec.rb"))
    end
  end

  def command(isolation, files)
    [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run", *files,
     "--preload", "spec/spec_helper.rb", "--isolation", isolation, "--format", "json"]
  end

  def run_evilution(isolation, files)
    Dir.mktmpdir("cross_file_restore") do |dir|
      copy_project(dir)
      out, err, status = Open3.capture3(*command(isolation, files), chdir: dir)
      raise "evilution failed (#{status.exitstatus}): #{err}" if out.strip.empty?

      report = JSON.parse(out)
      raise "evilution failed (#{status.exitstatus}): #{report["error"]}" if report.key?("error")

      report
    end
  end

  def subject_of(report, name)
    report.fetch("subjects").find { |subject| subject.fetch("name") == name }
  end

  %w[fork in_process].each do |isolation|
    context "under #{isolation} isolation" do
      let(:report) { run_evilution(isolation, %w[lib/limits.rb lib/checker.rb]) }

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
    scores = %w[fork in_process].map do |isolation|
      subject_of(run_evilution(isolation, %w[lib/limits.rb lib/checker.rb]), "Checker.within?").slice("killed", "survived")
    end

    expect(scores.first).to eq(scores.last)
  end
end
