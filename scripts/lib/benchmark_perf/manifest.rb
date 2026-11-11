# frozen_string_literal: true

require "yaml"
require_relative "run_result"

module BenchmarkPerf
  class ConfigError < StandardError; end

  Target = Struct.new(:name, :dir, :args, :env, keyword_init: true)

  # The benchmark corpus and the versions to compare. Relative target dirs
  # resolve against the manifest file's directory.
  class Manifest
    DEFAULT_VERSIONS = %w[HEAD worktree].freeze
    DEFAULT_REPEATS = 3

    attr_reader :targets, :versions, :repeats, :version_args

    def self.load(path)
      data = YAML.safe_load_file(path)
      raise ConfigError, "manifest must list targets:" unless data.is_a?(Hash) && data["targets"].is_a?(Array)

      from_hash(data, File.dirname(File.expand_path(path)))
    rescue Errno::ENOENT
      raise ConfigError, "manifest not found: #{path}"
    rescue Psych::SyntaxError => e
      raise ConfigError, "manifest is not valid YAML: #{e.message}"
    end

    def self.from_hash(data, base_dir)
      new(targets: data["targets"].map { |entry| build_target(entry, base_dir) },
          versions: data.fetch("versions", DEFAULT_VERSIONS),
          repeats: data.fetch("repeats", DEFAULT_REPEATS),
          version_args: data.fetch("version_args", {}))
    end

    def self.build_target(entry, base_dir)
      valid = entry.is_a?(Hash) && entry["name"] && entry["dir"]
      raise ConfigError, "each target needs a name and a dir: #{entry.inspect}" unless valid

      Target.new(name: entry["name"], dir: File.expand_path(entry["dir"], base_dir),
                 args: Array(entry["args"]), env: entry.fetch("env", {}))
    end

    private_class_method :from_hash, :build_target

    def initialize(targets:, versions:, repeats:, version_args:)
      @targets = targets
      @versions = versions
      @repeats = repeats
      @version_args = version_args
    end

    def with(versions: nil, repeats: nil)
      self.class.new(targets: targets, versions: versions || self.versions,
                     repeats: repeats || self.repeats, version_args: version_args)
    end
  end
end
