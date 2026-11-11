# frozen_string_literal: true

require "json"
require "stringio"
require "tmpdir"
require "yaml"
require_relative "../../../scripts/lib/benchmark_perf/cli"

RSpec.describe BenchmarkPerf::CLI do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir and example.run }
  end

  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def cli(argv, executor_factory: nil)
    described_class.new(argv, stdout: stdout, stderr: stderr, executor_factory: executor_factory,
                              now: -> { Time.new(2026, 11, 11, 10, 0, 0) })
  end

  def report_json
    JSON.generate("summary" => { "duration" => 1.0, "killtime" => 0.5 },
                  "killed" => [{ "file" => "a.rb", "line" => 1, "operator" => "cmp",
                                 "status" => "killed", "duration" => 0.5, "diff" => "" }])
  end

  it "re-renders the report from a saved run directory" do
    store = BenchmarkPerf::Store.new(@dir)
    store.save_meta("versions" => %w[A B], "labels" => { "A" => "a1", "B" => "b1" }, "repeats" => 1)
    %w[A B].each { |v| store.save(target: "fixture", version: v, repeat: 1, stdout: report_json, wall: 2.0) }

    expect(cli(["--from", @dir]).call).to eq(0)
    expect(File.read(File.join(@dir, "report.md"))).to include("## fixture", "a1", "b1")
    expect(stdout.string).to include(File.join(@dir, "report.md"))
  end

  it "exits 2 with a message when the manifest is missing" do
    expect(cli([File.join(@dir, "missing.yml")]).call).to eq(2)
    expect(stderr.string).to include("manifest not found")
  end

  it "exits 2 with usage when no manifest is given" do
    expect(cli([]).call).to eq(2)
    expect(stderr.string).to include("Usage")
  end

  it "passes version and repeat overrides to the executor and writes the report" do
    manifest_path = File.join(@dir, "bench.yml")
    File.write(manifest_path, YAML.dump("targets" => [{ "name" => "fixture", "dir" => @dir }]))
    out = File.join(@dir, "out")
    captured = nil
    factory = lambda do |manifest:, store:|
      captured = manifest
      expect(store.dir).to eq(out)
      runs = [BenchmarkPerf::RunResult.from_json(JSON.parse(report_json), wall: 1.0)]
      sample = BenchmarkPerf::VersionSample.new(runs: runs)
      { labels: { "v1" => "s1", "v2" => "s2" }, run: -> { { "fixture" => { "v1" => sample, "v2" => sample } } } }
    end

    status = cli([manifest_path, "--versions", "v1,v2", "--repeats", "1", "--out", out],
                 executor_factory: factory).call

    expect(status).to eq(0)
    expect(captured).to have_attributes(versions: %w[v1 v2], repeats: 1)
    expect(File.read(File.join(out, "report.md"))).to include("s1", "s2")
    expect(JSON.parse(File.read(File.join(out, "meta.json")))).to include("versions" => %w[v1 v2], "repeats" => 1)
  end

  it "defaults the output directory to a timestamped folder under .artifacts" do
    expect(described_class.default_out(Time.new(2026, 11, 11, 10, 0, 0)))
      .to eq(".artifacts/benchmark_perf/20261111-100000")
  end
end
