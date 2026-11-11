# frozen_string_literal: true

require_relative "manifest"
require_relative "store"

# Runs every version over every target, interleaving versions within each
# repeat so day-to-day machine drift hits all versions alike. All versions are
# wired into all targets first (untimed), so a bad ref or a broken bundle
# fails before hours of runs.
class BenchmarkPerf::Executor
  MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

  def initialize(manifest:, workspace:, runner:, store:, clock: MONOTONIC, log: $stderr)
    @manifest = manifest
    @workspace = workspace
    @runner = runner
    @store = store
    @clock = clock
    @log = log
  end

  def call
    gemfiles = prepare_all
    @manifest.targets.to_h { |target| [target.name, run_target(target, gemfiles)] }
  end

  private

  def prepare_all
    @manifest.targets.each_with_object({}) do |target, gemfiles|
      @manifest.versions.each { |ref| gemfiles[[target.name, ref]] = @workspace.prepare(target, ref) }
    end
  end

  def run_target(target, gemfiles)
    runs = @manifest.versions.to_h { |ref| [ref, []] }
    (1..@manifest.repeats).each do |repeat|
      @manifest.versions.each { |ref| runs[ref] << run_once(target, ref, repeat, gemfiles.fetch([target.name, ref])) }
    end
    runs.transform_values { |list| BenchmarkPerf::VersionSample.new(runs: list) }
  end

  def run_once(target, ref, repeat, gemfile)
    stdout, stderr, ok, wall = timed_run(target, ref, gemfile)
    result = BenchmarkPerf::Store.run_result(stdout, wall: wall)
    error = failure_message(result, stderr, ok)
    @store.save(target: target.name, version: ref, repeat: repeat, stdout: stdout, stderr: stderr, wall: wall,
                error: error)
    log_run(target, ref, repeat, wall, error)
    error ? BenchmarkPerf::RunResult.failed(error, wall: wall) : result
  end

  def timed_run(target, ref, gemfile)
    env = target.env.merge("BUNDLE_GEMFILE" => gemfile)
    started = @clock.call
    stdout, stderr, ok = @runner.call(command(target, ref), dir: target.dir, env: env)
    [stdout, stderr, ok, @clock.call - started]
  end

  # A run counts when evilution printed a report, whatever its exit status:
  # evilution exits non-zero when mutants survive.
  def failure_message(result, stderr, exit_ok)
    return nil unless result.failed?

    "exit #{exit_ok ? "success" : "failure"}: #{stderr_summary(stderr) || result.error}"
  end

  # A crash ends with its backtrace; the exception line says what went wrong.
  def stderr_summary(stderr)
    lines = stderr.lines.map(&:strip).reject(&:empty?)
    lines.find { |line| line.match?(/Error|Exception/) } || lines.first
  end

  def log_run(target, ref, repeat, wall, error)
    status = error ? " FAILED" : ""
    @log.puts(format("[%<target>s] repeat %<repeat>d/%<total>d %<ref>s %<wall>.1fs%<status>s",
                     target: target.name, repeat: repeat, total: @manifest.repeats, ref: ref, wall: wall,
                     status: status))
  end

  def command(target, ref)
    ["bundle", "exec", "ruby", File.join(@workspace.tree_for(ref), "exe", "evilution"),
     *target.args, *@manifest.version_args.fetch(ref, []), "--format", "json"]
  end
end
