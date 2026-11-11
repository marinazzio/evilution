# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "version_sample"

# Raw evilution output and run metadata on disk, so a report can be rebuilt
# without re-running:
#   <dir>/meta.json
#   <dir>/runs/<target>/<version>/<repeat>.json       raw stdout
#   <dir>/runs/<target>/<version>/<repeat>.stderr     raw stderr
#   <dir>/runs/<target>/<version>/<repeat>.meta.json  wall, error, names
class BenchmarkPerf::Store
  attr_reader :dir

  def initialize(dir)
    @dir = dir
  end

  def save(target:, version:, repeat:, stdout:, wall:, stderr: "", error: nil)
    run_dir = File.join(dir, "runs", BenchmarkPerf.slug(target), BenchmarkPerf.slug(version))
    FileUtils.mkdir_p(run_dir)
    File.write(File.join(run_dir, "#{repeat}.json"), stdout)
    File.write(File.join(run_dir, "#{repeat}.stderr"), stderr)
    meta = { "wall" => wall, "error" => error, "version" => version, "target" => target }
    File.write(File.join(run_dir, "#{repeat}.meta.json"), JSON.generate(meta))
  end

  def save_meta(meta)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "meta.json"), JSON.pretty_generate(meta))
  end

  def load
    meta = load_meta
    runs = Dir.glob(File.join(dir, "runs", "*", "*", "*.meta.json")).map { |path| load_run(path) }
    samples = runs.group_by(&:first).transform_values do |by_target|
      fill_missing(by_target.group_by { |entry| entry[1] }.transform_values { |entries| sample_of(entries) },
                   meta.fetch("versions", []))
    end
    [meta, samples]
  end

  def self.run_result(stdout, wall:, error: nil)
    return BenchmarkPerf::RunResult.failed(error, wall: wall) if error

    data = BenchmarkPerf.extract_json(stdout)
    reported = data["error"]
    return BenchmarkPerf::RunResult.failed(evilution_error(reported), wall: wall) if reported

    BenchmarkPerf::RunResult.from_json(data, wall: wall)
  rescue BenchmarkPerf::ParseError => e
    BenchmarkPerf::RunResult.failed(e.message, wall: wall)
  end

  # Evilution reports fatal errors (bad target, load failure) as {"error": {...}}.
  def self.evilution_error(reported)
    return "evilution error: #{reported}" unless reported.is_a?(Hash)

    "evilution #{reported["type"]}: #{reported["message"]}"
  end

  private

  def load_meta
    path = File.join(dir, "meta.json")
    File.exist?(path) ? JSON.parse(File.read(path)) : {}
  end

  def load_run(meta_path)
    meta = JSON.parse(File.read(meta_path))
    stdout = File.read(meta_path.sub(/\.meta\.json\z/, ".json"))
    [meta["target"], meta["version"], self.class.run_result(stdout, wall: meta["wall"], error: meta["error"])]
  end

  # An interrupted run leaves some (target, version) cells without any run.
  def fill_missing(by_version, versions)
    versions.each do |ref|
      by_version[ref] ||= BenchmarkPerf::VersionSample.new(runs: [BenchmarkPerf::RunResult.failed("not run", wall: 0.0)])
    end
    by_version
  end

  def sample_of(entries)
    BenchmarkPerf::VersionSample.new(runs: entries.map(&:last))
  end
end
