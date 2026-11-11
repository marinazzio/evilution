# frozen_string_literal: true

require "tmpdir"
require "yaml"
require_relative "../../../scripts/lib/benchmark_perf/manifest"

RSpec.describe BenchmarkPerf::Manifest do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir and example.run }
  end

  def write_manifest(data)
    path = File.join(@dir, "bench.yml")
    File.write(path, YAML.dump(data))
    path
  end

  let(:target) { { "name" => "fixture", "dir" => "corpus/fixture", "args" => ["lib"] } }

  it "applies defaults" do
    manifest = described_class.load(write_manifest("targets" => [target]))

    expect(manifest).to have_attributes(versions: %w[HEAD worktree], repeats: 3, version_args: {})
    expect(manifest.targets.first).to have_attributes(name: "fixture", args: ["lib"], env: {})
  end

  it "resolves a relative dir against the manifest's directory" do
    manifest = described_class.load(write_manifest("targets" => [target]))

    expect(manifest.targets.first.dir).to eq(File.join(@dir, "corpus/fixture"))
  end

  it "keeps an absolute dir" do
    manifest = described_class.load(write_manifest("targets" => [target.merge("dir" => "/abs/repo")]))

    expect(manifest.targets.first.dir).to eq("/abs/repo")
  end

  it "reads versions, repeats, version args and env" do
    data = { "versions" => %w[v1.4.0 HEAD], "repeats" => 2, "version_args" => { "v1.4.0" => ["--x"] },
             "targets" => [target.merge("env" => { "RUBYOPT" => "-Itest" })] }
    manifest = described_class.load(write_manifest(data))

    expect(manifest).to have_attributes(versions: %w[v1.4.0 HEAD], repeats: 2, version_args: { "v1.4.0" => ["--x"] })
    expect(manifest.targets.first.env).to eq("RUBYOPT" => "-Itest")
  end

  it "rejects a manifest without targets" do
    expect { described_class.load(write_manifest("versions" => ["HEAD"])) }
      .to raise_error(BenchmarkPerf::ConfigError, /targets/)
  end

  it "rejects a target without a name or dir" do
    expect { described_class.load(write_manifest("targets" => [{ "args" => [] }])) }
      .to raise_error(BenchmarkPerf::ConfigError, /name/)
  end

  it "reports a missing manifest file" do
    expect { described_class.load(File.join(@dir, "nope.yml")) }
      .to raise_error(BenchmarkPerf::ConfigError, /not found/)
  end

  it "overrides only the given fields" do
    manifest = described_class.load(write_manifest("targets" => [target])).with(repeats: 1)

    expect(manifest).to have_attributes(repeats: 1, versions: %w[HEAD worktree])
  end
end
