# frozen_string_literal: true

require "yaml"

module Evilution
  class Config
    CONFIG_FILES = %w[.evilution.yml config/evilution.yml].freeze

    DEFAULTS = {
      timeout: 30,
      format: :text,
      diff_base: nil,
      target: nil,
      min_score: 0.0,
      integration: :rspec,
      coverage: true,
      verbose: false,
      quiet: false,
      jobs: 1,
      fail_fast: nil,
      baseline: true,
      isolation: :auto,
      incremental: false,
      line_ranges: {},
      spec_files: []
    }.freeze

    attr_reader :target_files, :timeout, :format, :diff_base,
                :target, :min_score, :integration, :coverage, :verbose, :quiet,
                :jobs, :fail_fast, :baseline, :isolation, :incremental, :line_ranges, :spec_files

    def initialize(**options)
      file_options = options.delete(:skip_config_file) ? {} : load_config_file
      merged = DEFAULTS.merge(file_options).merge(options)
      warn_removed_options(merged, file_options)
      assign_attributes(merged)
      freeze
    end

    def json?
      format == :json
    end

    def text?
      format == :text
    end

    def diff?
      !diff_base.nil?
    end

    def line_ranges?
      !line_ranges.empty?
    end

    def target?
      !target.nil?
    end

    def fail_fast?
      !fail_fast.nil?
    end

    def baseline?
      baseline
    end

    def incremental?
      incremental
    end

    def self.file_options
      CONFIG_FILES.each do |path|
        next unless File.exist?(path)

        data = YAML.safe_load_file(path, symbolize_names: true)
        return data.is_a?(Hash) ? data : {}
      rescue Psych::SyntaxError, Psych::DisallowedClass => e
        raise ConfigError.new("failed to parse config file #{path}: #{e.message}", file: path)
      rescue SystemCallError => e
        raise ConfigError.new("cannot read config file #{path}: #{e.message}", file: path)
      end

      {}
    end

    # Generates a default config file template.
    def self.default_template
      <<~YAML
        # Evilution configuration
        # See: https://github.com/marinazzio/evilution

        # Per-mutation timeout in seconds (default: 30)
        # timeout: 30

        # Output format: text or json (default: text)
        # format: text

        # Minimum mutation score to pass (0.0 to 1.0, default: 0.0)
        # min_score: 0.0

        # Test integration: rspec (default: rspec)
        # integration: rspec

        # Number of parallel workers (default: 1)
        # jobs: 1

        # Stop after N surviving mutants (default: disabled)
        # fail_fast: 1

        # DEPRECATED: Coverage filtering is deprecated and will be removed
        # coverage: true
      YAML
    end

    private

    def validate_fail_fast(value)
      return nil if value.nil?

      value = Integer(value)
      raise ConfigError, "fail_fast must be a positive integer, got #{value}" unless value >= 1

      value
    rescue ::ArgumentError, ::TypeError
      raise ConfigError, "fail_fast must be a positive integer, got #{value.inspect}"
    end

    def assign_attributes(merged)
      @target_files = Array(merged[:target_files])
      @timeout = merged[:timeout]
      @format = merged[:format].to_sym
      @diff_base = merged[:diff_base]
      @target = merged[:target]
      @min_score = merged[:min_score].to_f
      @integration = merged[:integration].to_sym
      @coverage = merged[:coverage]
      @verbose = merged[:verbose]
      @quiet = merged[:quiet]
      @jobs = validate_jobs(merged[:jobs])
      @fail_fast = validate_fail_fast(merged[:fail_fast])
      @baseline = merged[:baseline]
      @isolation = validate_isolation(merged[:isolation])
      @incremental = merged[:incremental]
      @line_ranges = merged[:line_ranges] || {}
      @spec_files = Array(merged[:spec_files])
    end

    def validate_isolation(value)
      raise ConfigError, "isolation must be auto, fork, or in_process, got nil" if value.nil?

      value = value.to_sym
      raise ConfigError, "isolation must be auto, fork, or in_process, got #{value.inspect}" unless %i[auto fork in_process].include?(value)

      value
    end

    def validate_jobs(value)
      raise ConfigError, "jobs must be a positive integer, got #{value.inspect}" if value.is_a?(Float)

      value = Integer(value)
      raise ConfigError, "jobs must be a positive integer, got #{value}" unless value >= 1

      value
    rescue ::ArgumentError, ::TypeError
      raise ConfigError, "jobs must be a positive integer, got #{value.inspect}"
    end

    def warn_removed_options(_merged, file_options)
      if file_options.key?(:coverage)
        warn("Warning: 'coverage' in config file is deprecated and ignored. " \
             "This option will be removed in a future version.")
      end

      return unless file_options[:diff_base]

      warn("Warning: 'diff_base' in config file is deprecated and will be removed in a future version. " \
           "Use line-range targeting instead: evilution run lib/foo.rb:15-30")
    end

    def load_config_file
      self.class.file_options
    end
  end
end
