# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real over a class whose body builds its empty instance,
# `EMPTY = Bag.new([].freeze).freeze`, and goes on after it. A mutant that
# drops the `new` call there, `EMPTY = Bag.freeze`, freezes the class itself,
# and the rest of the body raises FrozenError. The original loads in any
# process that mutant has not touched, so the mutant broke the load and is
# detected.
RSpec.describe "A mutant that freezes its own class while the file loads", :aggregate_failures do
  project = File.expand_path("../../support/fixtures/frozen_class_load_failure_project", __dir__)
  root = File.expand_path("../../..", __dir__)

  run_evilution = lambda do |isolation|
    Dir.mktmpdir("frozen_class_load_failure") do |dir|
      FileUtils.cp_r(File.join(project, "."), dir)
      # The fixture's spec is kept under another name so this suite does not
      # load it as its own.
      FileUtils.mv(File.join(dir, "spec/bag_spec.rb.fixture"), File.join(dir, "spec/bag_spec.rb"))
      env = { "BUNDLE_GEMFILE" => ENV.fetch("BUNDLE_GEMFILE", File.join(root, "Gemfile")) }
      command = [RbConfig.ruby, "-rbundler/setup", "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run",
                 "lib/bag.rb", "--preload", "spec/spec_helper.rb",
                 "--isolation", isolation, "--format", "json"]
      out, err, status = Open3.capture3(env, *command, chdir: dir)
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

      it "counts the mutant as killed, saying what the load raised" do
        freezing = report.fetch("killed").find { |entry| entry.fetch("diff").end_with?("+   EMPTY = Bag.freeze") }

        expect(freezing).to include("error_class" => "FrozenError")
        # Ruby versions word the frozen receiver differently.
        expect(freezing.fetch("error_message")).to match(/\Aload failed: FrozenError: can't modify frozen ([Cc]lass|#<Class:Bag>): Bag\z/)
      end

      # The class the mutant froze is replaced by the original's, so the
      # mutants after it are judged against a class that loads again.
      it "reports no errors" do
        expect(report.dig("summary", "errors")).to eq(0)
        expect(report.fetch("errors", [])).to eq([])
      end
    end
  end

  it "scores the file the same under both isolations" do
    summaries = @reports.values.map { |report| report.fetch("summary").slice("total", "killed", "survived", "errors") }

    expect(summaries.first).to eq(summaries.last)
  end
end
