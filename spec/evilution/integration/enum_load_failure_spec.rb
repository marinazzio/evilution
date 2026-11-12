# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real over a model-like class whose `enum` takes its labels
# from a constant: `STATUSES = { "pending" => ..., "done" => ... }`. The model
# is autoloaded, as Rails loads one, so its `enum` call is evaluated with each
# mutation. A label blanked or emptied makes `enum` raise while the file loads.
# Like ActiveRecord's, this `enum` also raises when its class body is evaluated
# a second time, which putting the original back after the failed load does.
RSpec.describe "A mutant that makes an enum model fail to load", :aggregate_failures do
  project = File.expand_path("../../support/fixtures/enum_load_failure_project", __dir__)
  root = File.expand_path("../../..", __dir__)

  run_evilution = lambda do |isolation|
    Dir.mktmpdir("enum_load_failure") do |dir|
      FileUtils.cp_r(File.join(project, "."), dir)
      # The fixture's spec is kept under another name so this suite does not
      # load it as its own.
      FileUtils.mv(File.join(dir, "spec/breakdown_move_spec.rb.fixture"), File.join(dir, "spec/breakdown_move_spec.rb"))
      command = [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run",
                 "lib/breakdown_move.rb", "--preload", "spec/spec_helper.rb",
                 "--isolation", isolation, "--format", "json"]
      out, err, status = Open3.capture3(*command, chdir: dir)
      raise "evilution failed (#{status.exitstatus}): #{err}" if out.strip.empty?

      report = JSON.parse(out)
      raise "evilution failed (#{status.exitstatus}): #{report["error"]}" if report.key?("error")

      report
    end
  end

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

      it "counts a mutant that blanks an enum label as killed, saying what enum raised" do
        blank_label = load_kills.select { |entry| entry.fetch("error_message").include?("must not contain a blank name") }

        expect(blank_label).not_to be_empty
        expect(blank_label.map { |entry| entry.fetch("error_class") }.uniq).to eq(["ArgumentError"])
      end

      it "counts a mutant that empties the labels as killed" do
        emptied = load_kills.find { |entry| entry.fetch("error_message").include?("must not be empty") }

        expect(emptied).not_to be_nil
      end

      # The original is put back after each failed load, so the mutants after
      # it are judged against it and some of them survive.
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
