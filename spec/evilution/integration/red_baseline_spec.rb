# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real, in a process of its own, against a spec file that
# is red in the baseline.
RSpec.describe "A red baseline", :aggregate_failures do
  let(:project) { File.expand_path("../../support/fixtures/red_baseline_project", __dir__) }
  let(:root) { File.expand_path("../../..", __dir__) }

  # Where each framework keeps the fixture's tests, and how evilution is told
  # to run them.
  frameworks = {
    "RSpec" => { file: "spec/calc_spec.rb", variant: "%s", flags: [], isolations: %w[fork in_process] },
    "Minitest" => { file: "test/calc_test.rb", variant: "minitest.%s", flags: %w[--integration minitest],
                    isolations: %w[fork in_process] },
    "Test::Unit" => { file: "test/calc_test.rb", variant: "test_unit.%s", flags: %w[--integration test-unit],
                      isolations: %w[fork in_process] }
  }

  # The fixture's tests are kept under other names so this suite does not
  # load them as its own.
  def copy_project(dir, framework, variant)
    FileUtils.cp_r(File.join(project, "."), dir)
    file = File.join(dir, framework.fetch(:file))
    FileUtils.mv("#{file}.#{format(framework.fetch(:variant), variant)}", file)
  end

  def command(framework, isolation)
    [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run", "lib/calc.rb",
     "--isolation", isolation, "--format", "json", *framework.fetch(:flags)]
  end

  def run_evilution(framework, variant, isolation)
    Dir.mktmpdir("red_baseline") do |dir|
      copy_project(dir, framework, variant)
      out, err, status = Open3.capture3(*command(framework, isolation), chdir: dir)
      raise "evilution failed (#{status.exitstatus}): #{err}" if out.strip.empty?

      report = JSON.parse(out)
      raise "evilution failed (#{status.exitstatus}): #{report["error"]}" if report.key?("error")

      report
    end
  end

  def subjects_of(report, bucket)
    methods = { (4..6) => "double", (8..10) => "triple", (12..14) => "half" }
    report.fetch(bucket).map { |entry| methods.find { |lines, _| lines.cover?(entry.fetch("line")) }.last }.uniq.sort
  end

  frameworks.each do |name, framework|
    context "with #{name}" do
      framework.fetch(:isolations).each do |isolation|
        context "under #{isolation} isolation" do
          # An example that fails whatever the code does fails in every mutation
          # run. That is a kill only where a passing example fails too.
          context "with an example that fails every time" do
            let(:report) { run_evilution(framework, "red", isolation) }

            it "counts a kill only where something that was passing fails" do
              expect(subjects_of(report, "killed")).to eq(["double"])
              expect(subjects_of(report, "neutral")).to eq(%w[half triple])
              expect(report.dig("summary", "survived")).to eq(0)
            end

            it "says why the others have no verdict" do
              reasons = report.fetch("neutral").map { |entry| entry.fetch("neutral_reason") }.uniq

              expect(reasons).to eq([{ "kind" => "baseline_failure", "detail" => framework.fetch(:file) }])
              expect(report.dig("summary", "baseline_neutralized")).to eq(report.dig("summary", "neutral"))
              expect(report.dig("summary", "baseline_failures").first.fetch("failing_examples")).to eq(1)
            end
          end

          # A failure the mutation runs do not reproduce says nothing about them:
          # their tests passed, and what survives is a real gap.
          context "with an example that failed in the baseline only" do
            let(:report) { run_evilution(framework, "flaky", isolation) }

            it "reports survivors as survivors and kills as kills" do
              expect(subjects_of(report, "survived")).to eq(["half"])
              expect(subjects_of(report, "killed")).to eq(%w[double triple])
              expect(report.dig("summary", "neutral")).to eq(0)
              expect(report.dig("summary", "baseline_failures").length).to eq(1)
            end
          end
        end
      end
    end
  end
end
