# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real over a file whose constant is computed while the
# file loads: `NAMES = %w[add sub].map(&:to_sym).freeze`. A mutation of that
# expression can raise before any test runs -- `nil.map` does -- and such a
# mutant is detected as surely as one that fails a test.
RSpec.describe "A mutant that makes its file fail to load", :aggregate_failures do
  project = File.expand_path("../../support/fixtures/load_failure_project", __dir__)
  root = File.expand_path("../../..", __dir__)

  run_evilution = lambda do |isolation|
    Dir.mktmpdir("load_failure") do |dir|
      FileUtils.cp_r(File.join(project, "."), dir)
      # The fixture's spec is kept under another name so this suite does not
      # load it as its own.
      FileUtils.mv(File.join(dir, "spec/operators_spec.rb.fixture"), File.join(dir, "spec/operators_spec.rb"))
      command = [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run",
                 "lib/operators.rb", "--preload", "spec/spec_helper.rb",
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

  %w[fork in_process].each do |isolation|
    context "under #{isolation} isolation" do
      let(:report) { @reports.fetch(isolation) }
      let(:load_kills) { report.fetch("killed").select { |entry| entry["error_message"].to_s.start_with?("load failed: ") } }

      it "reports no errors" do
        expect(report.dig("summary", "errors")).to eq(0)
        expect(report.fetch("errors", [])).to be_empty
      end

      it "counts the mutant as killed, saying what the load raised" do
        nil_receiver = load_kills.find { |entry| entry.fetch("diff").include?("nil.map") }

        expect(nil_receiver).not_to be_nil
        # Ruby quotes the method name with a backtick before 3.4.
        expect(nil_receiver.fetch("error_message")).to match(/\Aload failed: NoMethodError: undefined method [`']map' for nil/)
        expect(nil_receiver.fetch("error_class")).to eq("NoMethodError")
      end

      # The file is put back after a failed load, so the mutants after it are
      # judged against the original and some of them survive.
      it "goes on to judge the mutants after it on their own" do
        expect(report.dig("summary", "survived")).to be_positive
        expect(report.fetch("killed").size).to be > load_kills.size
      end
    end
  end

  it "scores the file the same under both isolations" do
    summaries = @reports.values.map { |report| report.fetch("summary").slice("total", "killed", "survived", "errors") }

    expect(summaries.first).to eq(summaries.last)
  end
end
