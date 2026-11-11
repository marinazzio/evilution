# frozen_string_literal: true

require "optparse"
require "tmpdir"
require_relative "command_runner"
require_relative "executor"
require_relative "report"
require_relative "workspace"

# Command-line entry point. Run mode benchmarks a manifest; --from DIR
# re-renders the report of an earlier run from its saved output.
class BenchmarkPerf::CLI
  USAGE = <<~TEXT
    Usage:
      scripts/benchmark_perf MANIFEST.yml [--versions a,b,c] [--repeats N] [--out DIR]
      scripts/benchmark_perf --from DIR
  TEXT
  REPO_ROOT = File.expand_path("../../..", __dir__)

  # Real wiring: a workspace over this checkout, exporting old refs into a
  # temp dir that lives for the whole run.
  DEFAULT_EXECUTOR_FACTORY = lambda do |manifest:, store:|
    runner = BenchmarkPerf::CommandRunner.new
    workspace = BenchmarkPerf::Workspace.new(repo_root: REPO_ROOT, tmp_root: Dir.mktmpdir("benchmark_perf"),
                                             runner: runner)
    executor = BenchmarkPerf::Executor.new(manifest: manifest, workspace: workspace, runner: runner, store: store)
    { labels: manifest.versions.to_h { |ref| [ref, workspace.label_for(ref)] }, run: -> { executor.call } }
  end

  def self.default_out(time)
    File.join(".artifacts", "benchmark_perf", time.strftime("%Y%m%d-%H%M%S"))
  end

  def initialize(argv, stdout: $stdout, stderr: $stderr, executor_factory: nil, now: -> { Time.now })
    @argv = argv.dup
    @stdout = stdout
    @stderr = stderr
    @executor_factory = executor_factory || DEFAULT_EXECUTOR_FACTORY
    @now = now
    @options = {}
  end

  def call
    parser.parse!(@argv)
    return rebuild(@options[:from]) if @options[:from]
    return usage_error if @argv.empty?

    benchmark(@argv.first)
  rescue BenchmarkPerf::ConfigError, OptionParser::ParseError => e
    @stderr.puts("benchmark_perf: #{e.message}")
    2
  end

  private

  def parser
    OptionParser.new do |opts|
      opts.banner = USAGE
      opts.on("--versions LIST", Array, "Versions to compare (git refs or worktree); first is the baseline") do |v|
        @options[:versions] = v
      end
      opts.on("--repeats N", Integer, "Runs per version per target") { |n| @options[:repeats] = n }
      opts.on("--out DIR", "Output directory") { |dir| @options[:out] = dir }
      opts.on("--from DIR", "Re-render the report of a saved run") { |dir| @options[:from] = dir }
    end
  end

  def usage_error
    @stderr.puts(USAGE)
    2
  end

  def load_manifest(path)
    BenchmarkPerf::Manifest.load(path).with(versions: @options[:versions], repeats: @options[:repeats])
  end

  def benchmark(manifest_path)
    manifest = load_manifest(manifest_path)
    store = BenchmarkPerf::Store.new(@options[:out] || self.class.default_out(@now.call))
    execution = @executor_factory.call(manifest: manifest, store: store)
    save_meta(store, manifest, execution[:labels])
    write_report(store.dir, manifest.versions, execution[:labels], execution[:run].call, manifest.repeats)
  end

  def save_meta(store, manifest, labels)
    store.save_meta("versions" => manifest.versions, "labels" => labels, "repeats" => manifest.repeats)
  end

  def rebuild(dir)
    meta, samples = BenchmarkPerf::Store.new(dir).load
    raise BenchmarkPerf::ConfigError, "no runs saved in #{dir}" if samples.empty?

    versions = meta.fetch("versions") { samples.values.first.keys }
    write_report(dir, versions, meta.fetch("labels", {}), samples, meta.fetch("repeats", 0))
  end

  def write_report(dir, versions, labels, samples, repeats)
    report = BenchmarkPerf::Report.new(versions: versions, version_labels: labels, samples: samples,
                                       repeats: repeats, generated_at: @now.call)
    path = File.join(dir, "report.md")
    File.write(path, report.to_markdown)
    @stdout.puts(path)
    0
  end
end
