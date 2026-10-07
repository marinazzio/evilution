# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "fileutils"

# A mutation can turn a loop into one that never ends. Under in_process
# isolation nothing but the per-mutation timeout stops it, and every test that
# reaches the loop has to be stopped, not the first one only.
RSpec.describe "A mutation that loops forever under in_process isolation", :aggregate_failures do
  let(:project) { File.expand_path("../../support/fixtures/looping_project", __dir__) }
  let(:root) { File.expand_path("../../..", __dir__) }

  # The fixture's tests are kept under other names so this suite does not
  # load them as its own.
  frameworks = {
    "RSpec" => { file: "spec/spin_spec.rb", variant: "rspec", flags: [] },
    "Minitest" => { file: "test/spin_test.rb", variant: "minitest", flags: %w[--integration minitest] },
    "Test::Unit" => { file: "test/spin_test.rb", variant: "test_unit", flags: %w[--integration test-unit] }
  }

  # Long enough for a healthy run on a slow machine, short enough that a run
  # which hangs fails the example instead of the suite.
  time_limit = 90

  def copy_project(dir, framework)
    FileUtils.cp_r(File.join(project, "."), dir)
    file = File.join(dir, framework.fetch(:file))
    FileUtils.mv("#{file}.#{framework.fetch(:variant)}", file)
  end

  def command(framework)
    [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run", "lib/spin.rb",
     "--isolation", "in_process", "--timeout", "2", "--no-baseline", "--format", "json", *framework.fetch(:flags)]
  end

  def capture(command, dir, time_limit)
    Open3.popen3(*command, chdir: dir) do |stdin, stdout, stderr, wait|
      stdin.close
      out = Thread.new { stdout.read }
      err = Thread.new { stderr.read }
      unless wait.join(time_limit)
        Process.kill("KILL", wait.pid)
        raise "evilution did not finish within #{time_limit}s"
      end

      [out.value, err.value]
    end
  end

  def run_evilution(framework, time_limit)
    Dir.mktmpdir("looping") do |dir|
      copy_project(dir, framework)
      out, err = capture(command(framework), dir, time_limit)
      raise "evilution failed: #{err}" if out.strip.empty?

      report = JSON.parse(out)
      raise "evilution failed: #{report["error"]}" if report.key?("error")

      report
    end
  end

  frameworks.each do |name, framework|
    context "with #{name}" do
      let(:summary) { run_evilution(framework, time_limit).fetch("summary") }

      it "reports the mutation as timed out and goes on to judge the ones that follow" do
        expect(summary.fetch("timed_out")).to be > 0
        expect(summary.fetch("errors")).to eq(0)
        expect(summary.fetch("killed")).to be > 0
        expect(summary.fetch("survived")).to be > 0
        expect(summary.fetch("killed") + summary.fetch("survived") + summary.fetch("timed_out"))
          .to eq(summary.fetch("total"))
      end
    end
  end
end
