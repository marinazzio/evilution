# frozen_string_literal: true

require "json"
require "stringio"
require "tmpdir"
require_relative "../../../scripts/lib/benchmark_perf/executor"
require_relative "fake_runner"
require_relative "fake_workspace"

RSpec.describe BenchmarkPerf::Executor do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir and example.run }
  end

  let(:report) do
    JSON.generate("summary" => { "duration" => 1.0, "killtime" => 0.5 },
                  "killed" => [{ "file" => "a.rb", "line" => 1, "operator" => "cmp",
                                 "status" => "killed", "duration" => 0.5, "diff" => "" }])
  end
  let(:target) { BenchmarkPerf::Target.new(name: "fixture", dir: "/corpus", args: ["lib"], env: { "X" => "1" }) }
  let(:manifest) do
    BenchmarkPerf::Manifest.new(targets: [target], versions: %w[A B], repeats: 2, version_args: { "B" => ["--b"] })
  end
  let(:workspace) { BenchmarkPerfFakeWorkspace.new }
  let(:ticks) { (0..).step(5.0).each }

  def executor(runner, workspace: self.workspace)
    described_class.new(manifest: manifest, workspace: workspace, runner: runner,
                        store: BenchmarkPerf::Store.new(@dir), clock: -> { ticks.next }, log: StringIO.new)
  end

  def evilution_calls(runner)
    runner.calls.select { |c| c[:cmd].include?("ruby") }
  end

  it "prepares every version before timing and interleaves versions per repeat" do
    runner = BenchmarkPerfFakeRunner.new { |_cmd| [report, "", true] }
    executor(runner).call

    expect(workspace.prepared).to eq([%w[fixture A], %w[fixture B]])
    trees = evilution_calls(runner).map { |c| c[:cmd][3] }
    expect(trees).to eq(%w[/trees/A/exe/evilution /trees/B/exe/evilution] * 2)
  end

  it "runs evilution with target args, version args, JSON format, env and the generated Gemfile" do
    runner = BenchmarkPerfFakeRunner.new { |_cmd| [report, "", true] }
    executor(runner).call

    call = evilution_calls(runner)[1]
    expect(call[:cmd]).to eq(%w[bundle exec ruby /trees/B/exe/evilution lib --b --format json])
    expect(call).to include(dir: "/corpus",
                            env: { "X" => "1", "BUNDLE_GEMFILE" => "/corpus/Gemfile.benchmark_perf.B" })
  end

  it "measures wall time with the clock" do
    runner = BenchmarkPerfFakeRunner.new { |_cmd| [report, "", true] }

    expect(executor(runner).call["fixture"]["A"].wall_median).to eq(5.0)
  end

  it "counts a non-zero exit with a valid report as a successful run" do
    runner = BenchmarkPerfFakeRunner.new { |_cmd| [report, "", false] }

    expect(executor(runner).call["fixture"]["A"]).not_to be_failed
  end

  it "marks a version failed when it never produces a report and keeps the others" do
    runner = BenchmarkPerfFakeRunner.new do |cmd|
      cmd.include?("/trees/B/exe/evilution") ? ["", "LoadError\nboom", false] : [report, "", true]
    end
    samples = executor(runner).call

    expect(samples["fixture"]["A"]).not_to be_failed
    expect(samples["fixture"]["B"]).to be_failed
    expect(samples["fixture"]["B"].errors.first).to eq("exit failure: LoadError")
  end

  it "reports the exception line of a crash, not the last backtrace line" do
    crash = "/trees/B/lib/x.rb:1:in 'require': cannot load such file -- prism (LoadError)\n" \
            "\tfrom /trees/B/exe/evilution:5:in '<main>'\n"
    runner = BenchmarkPerfFakeRunner.new { |_cmd| ["", crash, false] }

    expect(executor(runner).call["fixture"]["A"].errors.first)
      .to eq("exit failure: /trees/B/lib/x.rb:1:in 'require': cannot load such file -- prism (LoadError)")
  end

  it "stores stderr for every run" do
    runner = BenchmarkPerfFakeRunner.new { |_cmd| [report, "warning: x\n", true] }
    executor(runner).call

    expect(Dir.glob(File.join(@dir, "runs", "fixture", "*", "*.stderr")).size).to eq(4)
  end

  it "marks a run failed when evilution reports an error instead of results" do
    error_report = JSON.generate("error" => { "type" => "parse_error", "message" => "cannot read lib" })
    runner = BenchmarkPerfFakeRunner.new { |_cmd| [error_report, "", false] }
    sample = executor(runner).call["fixture"]["A"]

    expect(sample).to be_failed
    expect(sample.errors.first).to eq("exit failure: evilution parse_error: cannot read lib")
  end

  it "stops before any timed run when preparing a version fails" do
    runner = BenchmarkPerfFakeRunner.new { |_cmd| [report, "", true] }

    expect { executor(runner, workspace: BenchmarkPerfFakeWorkspace.new(fail_on: "B")).call }
      .to raise_error(BenchmarkPerf::ConfigError)
    expect(evilution_calls(runner)).to be_empty
  end

  it "stores every run" do
    runner = BenchmarkPerfFakeRunner.new { |_cmd| [report, "", true] }
    executor(runner).call

    expect(Dir.glob(File.join(@dir, "runs", "fixture", "*", "*.meta.json")).size).to eq(4)
  end
end
