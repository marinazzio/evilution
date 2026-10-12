# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real against an ActiveSupport::Concern with a `prepended`
# block, in a process of its own.
#
# One example reads what the block declares through a class loaded before the
# run, one through a class that prepends the concern only inside the example.
# No example calls `Auditable.unused`, so its mutations survive -- unless the
# concern is left without its block when the mutated file is evaluated, and
# the class that prepends it during the run gets none of its declarations.
RSpec.describe "A concern's prepended block", :aggregate_failures do
  project = File.expand_path("../../support/fixtures/prepended_concern_project", __dir__)
  root = File.expand_path("../../..", __dir__)

  run_evilution = lambda do |isolation|
    Dir.mktmpdir("prepended_concern") do |dir|
      FileUtils.cp_r(File.join(project, "."), dir)
      # The fixture's spec is kept under another name so this suite does not
      # load it as its own.
      FileUtils.mv(File.join(dir, "spec/auditable_spec.rb.fixture"), File.join(dir, "spec/auditable_spec.rb"))
      command = [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run",
                 "lib/auditable.rb", "--preload", "spec/spec_helper.rb",
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

      it "runs without errors" do
        expect(report.dig("summary", "errors")).to eq(0)
        expect(report.dig("summary", "neutral")).to eq(0)
      end

      it "kills nothing in a method no example calls" do
        unused = report.fetch("subjects").find { |subject| subject.fetch("name") == "Auditable.unused" }

        expect(unused.fetch("total")).to be_positive
        expect(unused.fetch("killed")).to eq(0)
      end
    end
  end
end
