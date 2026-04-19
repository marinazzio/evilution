# frozen_string_literal: true

require "yaml"
require_relative "spec_selector"

class Evilution::Config
  CONFIG_FILES = %w[.evilution.yml config/evilution.yml].freeze

  DEFAULTS = {
    timeout: 30,
    format: :text,
    target: nil,
    min_score: 0.0,
    integration: :rspec,
    verbose: false,
    quiet: false,
    jobs: 1,
    fail_fast: nil,
    baseline: true,
    isolation: :auto,
    incremental: false,
    suggest_tests: false,
    progress: true,
    save_session: false,
    line_ranges: {},
    spec_files: [],
    ignore_patterns: [],
    show_disabled: false,
    baseline_session: nil,
    skip_heredoc_literals: false,
    related_specs_heuristic: false,
    fallback_to_full_suite: false,
    preload: nil,
    spec_mappings: {},
    spec_pattern: nil
  }.freeze

  attr_reader :target_files, :timeout, :format,
              :target, :min_score, :integration, :verbose, :quiet,
              :jobs, :fail_fast, :baseline, :isolation, :incremental, :suggest_tests,
              :progress, :save_session, :line_ranges, :spec_files, :hooks,
              :ignore_patterns, :show_disabled, :baseline_session,
              :skip_heredoc_literals, :related_specs_heuristic,
              :fallback_to_full_suite, :preload, :spec_mappings, :spec_pattern,
              :spec_selector

  def initialize(**options)
    file_options = options.delete(:skip_config_file) ? {} : load_config_file
    merged = DEFAULTS.merge(file_options).merge(options)
    assign_attributes(merged)
    freeze
  end

  def json?
    format == :json
  end

  def text?
    format == :text
  end

  def html?
    format == :html
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

  def suggest_tests?
    suggest_tests
  end

  def progress?
    progress
  end

  def save_session?
    save_session
  end

  def show_disabled?
    show_disabled
  end

  def skip_heredoc_literals?
    skip_heredoc_literals
  end

  def related_specs_heuristic?
    related_specs_heuristic
  end

  def fallback_to_full_suite?
    fallback_to_full_suite
  end

  def self.file_options
    CONFIG_FILES.each do |path|
      next unless File.exist?(path)

      data = YAML.safe_load_file(path, symbolize_names: true)
      return data.is_a?(Hash) ? data : {}
    rescue Psych::SyntaxError, Psych::DisallowedClass => e
      raise Evilution::ConfigError.new("failed to parse config file #{path}: #{e.message}", file: path)
    rescue SystemCallError => e
      raise Evilution::ConfigError.new("cannot read config file #{path}: #{e.message}", file: path)
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

      # Test integration: rspec, minitest (default: rspec)
      # integration: rspec

      # Number of parallel workers (default: 1)
      # jobs: 1

      # Stop after N surviving mutants (default: disabled)
      # fail_fast: 1

      # Generate concrete test code in suggestions, matching integration (default: false)
      # suggest_tests: false

      # Skip all string literal mutations inside heredocs (default: false).
      # Useful for Rails apps where heredoc content (SQL, templates, fixtures)
      # rarely has meaningful test coverage and produces noisy survivors.
      # skip_heredoc_literals: true

      # Opt into the RelatedSpecHeuristic, which appends request/integration/
      # feature/system specs for mutations that touch `.includes(...)` calls
      # (default: false). Off by default because the fan-out can be heavy and
      # push runs over the per-mutation timeout. Enable if you need coverage
      # of N+1 regressions that only surface in higher-level specs.
      # related_specs_heuristic: true

      # When no matching spec resolves for a mutation's source file, the
      # default is to skip that mutation and mark it :unresolved in the
      # report (a coverage gap signal). Set to true to fall back to running
      # the entire test suite for such mutations instead (slow, high memory).
      # fallback_to_full_suite: false

      # Preload file required in the parent process before forking workers.
      # For Rails projects, spec/rails_helper.rb or test/test_helper.rb is
      # auto-detected when isolation resolves to :fork. Set to false to disable.
      # preload: spec/rails_helper.rb # or test/test_helper.rb

      # Hooks: Ruby files returning a Proc, keyed by lifecycle event
      # hooks:
      #   worker_process_start: config/evilution_hooks/worker_start.rb
      #   mutation_insert_pre: config/evilution_hooks/mutation_pre.rb

      # AST patterns to skip during mutation generation (default: [])
      # See docs/ast_pattern_syntax.md for pattern syntax
      # ignore_patterns:
      #   - "call{name=info, receiver=call{name=logger}}"
      #   - "call{name=debug|warn}"
    YAML
  end

  private

  def validate_fail_fast(value)
    return nil if value.nil?

    value = Integer(value)
    raise Evilution::ConfigError, "fail_fast must be a positive integer, got #{value}" unless value >= 1

    value
  rescue ::ArgumentError, ::TypeError
    raise Evilution::ConfigError, "fail_fast must be a positive integer, got #{value.inspect}"
  end

  def assign_attributes(merged) # rubocop:disable Metrics/AbcSize
    @target_files = Array(merged[:target_files])
    @timeout = merged[:timeout]
    @format = merged[:format].to_sym
    @target = merged[:target]
    @min_score = merged[:min_score].to_f
    @integration = validate_integration(merged[:integration])
    @verbose = merged[:verbose]
    @quiet = merged[:quiet]
    @jobs = validate_jobs(merged[:jobs])
    @fail_fast = validate_fail_fast(merged[:fail_fast])
    @baseline = merged[:baseline]
    @isolation = validate_isolation(merged[:isolation])
    @incremental = merged[:incremental]
    @suggest_tests = merged[:suggest_tests]
    @progress = merged[:progress]
    @save_session = merged[:save_session]
    @line_ranges = merged[:line_ranges] || {}
    @spec_files = Array(merged[:spec_files])
    @ignore_patterns = validate_ignore_patterns(merged[:ignore_patterns])
    @show_disabled = merged[:show_disabled]
    @baseline_session = merged[:baseline_session]
    @skip_heredoc_literals = merged[:skip_heredoc_literals]
    @related_specs_heuristic = merged[:related_specs_heuristic]
    @fallback_to_full_suite = merged[:fallback_to_full_suite]
    @hooks = validate_hooks(merged[:hooks])
    @preload = validate_preload(merged[:preload])
    @spec_mappings = validate_spec_mappings(merged[:spec_mappings])
    @spec_pattern = validate_spec_pattern(merged[:spec_pattern])
    @spec_selector = build_spec_selector
  end

  def build_spec_selector
    Evilution::SpecSelector.new(
      spec_files: @spec_files,
      spec_mappings: @spec_mappings,
      spec_pattern: @spec_pattern
    )
  end

  def validate_spec_mappings(value)
    return {} if value.nil?

    raise Evilution::ConfigError, "spec_mappings must be a Hash, got #{value.class}" unless value.is_a?(Hash)

    normalized = value.each_with_object({}) do |(source, specs), acc|
      key = source.to_s
      acc[key] = normalize_spec_mappings_value(key, specs)
    end

    warn_missing_spec_mappings(normalized)
    normalized
  end

  def normalize_spec_mappings_value(source, specs)
    case specs
    when String then [specs]
    when Array
      specs.each do |entry|
        unless entry.is_a?(String)
          raise Evilution::ConfigError,
                "spec_mappings[#{source.inspect}] entries must be string paths, got #{entry.class}"
        end
      end
      specs
    else
      raise Evilution::ConfigError,
            "spec_mappings[#{source.inspect}] must be a string or array of strings, got #{specs.class}"
    end
  end

  def warn_missing_spec_mappings(mappings)
    mappings.each do |source, specs|
      specs.each do |spec_path|
        next if File.exist?(spec_path)

        warn "[evilution] spec_mappings[#{source.inspect}]: #{spec_path} not found, skipping"
      end
    end
  end

  def validate_spec_pattern(value)
    return nil if value.nil?
    return value if value.is_a?(String)

    raise Evilution::ConfigError, "spec_pattern must be nil or a String glob, got #{value.class}"
  end

  def validate_preload(value)
    return nil if value.nil?
    return false if value == false
    return value if value.is_a?(String)

    raise Evilution::ConfigError, "preload must be nil, false, or a String path, got #{value.inspect}"
  end

  def validate_integration(value)
    raise Evilution::ConfigError, "integration must be rspec or minitest, got nil" if value.nil?

    value = value.to_sym
    unless %i[rspec minitest].include?(value)
      raise Evilution::ConfigError,
            "integration must be rspec or minitest, got #{value.inspect}"
    end

    value
  end

  def validate_isolation(value)
    raise Evilution::ConfigError, "isolation must be auto, fork, or in_process, got nil" if value.nil?

    value = value.to_sym
    raise Evilution::ConfigError, "isolation must be auto, fork, or in_process, got #{value.inspect}" unless %i[auto fork
                                                                                                                in_process].include?(value)

    value
  end

  def validate_jobs(value)
    raise Evilution::ConfigError, "jobs must be a positive integer, got #{value.inspect}" if value.is_a?(Float)

    value = Integer(value)
    raise Evilution::ConfigError, "jobs must be a positive integer, got #{value}" unless value >= 1

    value
  rescue ::ArgumentError, ::TypeError
    raise Evilution::ConfigError, "jobs must be a positive integer, got #{value.inspect}"
  end

  def validate_ignore_patterns(value)
    patterns = Array(value)
    patterns.each do |pattern|
      unless pattern.is_a?(String)
        raise Evilution::ConfigError,
              "ignore_patterns must be an array of strings, got #{pattern.class} (#{pattern.inspect})"
      end
    end
    patterns
  end

  def validate_hooks(value)
    return {} if value.nil?
    raise Evilution::ConfigError, "hooks must be a mapping of event names to file paths, got #{value.class}" unless value.is_a?(Hash)

    value
  end

  def load_config_file
    self.class.file_options
  end
end
