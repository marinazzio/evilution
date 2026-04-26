# frozen_string_literal: true

require "yaml"
require_relative "spec_resolver"
require_relative "spec_selector"

class Evilution::Config
  CONFIG_FILES = %w[.evilution.yml config/evilution.yml].freeze

  DEFAULTS = {
    timeout: 30, format: :text, target: nil, min_score: 0.0, integration: :rspec,
    verbose: false, quiet: false, jobs: 1, fail_fast: nil, baseline: true,
    isolation: :auto, incremental: false, suggest_tests: false, progress: true,
    save_session: false, line_ranges: {}, spec_files: [], ignore_patterns: [],
    show_disabled: false, baseline_session: nil, skip_heredoc_literals: false,
    related_specs_heuristic: false, fallback_to_full_suite: false, preload: nil,
    spec_mappings: {}, spec_pattern: nil, example_targeting: true,
    example_targeting_fallback: :full_file,
    example_targeting_cache: { max_files: 50, max_blocks: 10_000 },
    quiet_children: false, quiet_children_dir: "tmp/evilution_children"
  }.freeze

  attr_reader :target_files, :timeout, :format,
              :target, :min_score, :integration, :verbose, :quiet,
              :jobs, :fail_fast, :baseline, :isolation, :incremental, :suggest_tests,
              :progress, :save_session, :line_ranges, :spec_files, :hooks,
              :ignore_patterns, :show_disabled, :baseline_session,
              :skip_heredoc_literals, :related_specs_heuristic,
              :fallback_to_full_suite, :preload, :spec_mappings, :spec_pattern,
              :example_targeting, :example_targeting_fallback, :example_targeting_cache,
              :spec_selector, :quiet_children, :quiet_children_dir

  def initialize(**options)
    skip_file = options.delete(:skip_config_file) ? true : false
    merged = Sources.merge(explicit: options, skip_file: skip_file)
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

  def example_targeting?
    example_targeting
  end

  def fallback_to_full_suite?
    fallback_to_full_suite
  end

  def self.file_options
    FileLoader.load
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
      # For Rails projects, the autodetect chain tries (in order):
      # spec/rails_helper.rb -> spec/spec_helper.rb -> test/test_helper.rb
      # when isolation resolves to :fork. Set to false to disable.
      # preload: spec/rails_helper.rb # or spec/spec_helper.rb, test/test_helper.rb

      # Hooks: Ruby files returning a Proc, keyed by lifecycle event
      # hooks:
      #   worker_process_start: config/evilution_hooks/worker_start.rb
      #   mutation_insert_pre: config/evilution_hooks/mutation_pre.rb

      # Per-mutation example targeting (default: true). When enabled, Evilution
      # parses resolved spec files and restricts each mutation run to examples
      # whose bodies reference the mutated method/class token. Set to false
      # to run every example in the resolved spec files. You can also disable
      # without editing the file by exporting EV_DISABLE_EXAMPLE_TARGETING=1.
      # example_targeting: true

      # Behavior when targeting finds no matching example (default: full_file).
      # full_file  - run every example in the resolved spec files
      # unresolved - mark the mutation :unresolved and skip
      # example_targeting_fallback: full_file

      # LRU cache bounds for the spec AST parser that powers example targeting.
      # example_targeting_cache:
      #   max_files: 50
      #   max_blocks: 10000

      # AST patterns to skip during mutation generation (default: [])
      # See docs/ast_pattern_syntax.md for pattern syntax
      # ignore_patterns:
      #   - "call{name=info, receiver=call{name=logger}}"
      #   - "call{name=debug|warn}"
    YAML
  end

  private

  def assign_attributes(merged)
    assign_simple_attributes(merged)
    assign_validated_attributes(merged)
    assign_example_targeting(merged)
    @spec_selector = Builders::SpecSelector.call(
      spec_files: @spec_files,
      spec_mappings: @spec_mappings,
      spec_pattern: @spec_pattern,
      integration: @integration
    )
  end

  def assign_simple_attributes(merged)
    @target_files            = Array(merged[:target_files])
    @timeout                 = merged[:timeout]
    @format                  = merged[:format].to_sym
    @target                  = merged[:target]
    @min_score               = merged[:min_score].to_f
    @verbose                 = merged[:verbose]
    @quiet                   = merged[:quiet]
    @baseline                = merged[:baseline]
    @incremental             = merged[:incremental]
    @suggest_tests           = merged[:suggest_tests]
    @progress                = merged[:progress]
    @save_session            = merged[:save_session]
    @line_ranges             = merged[:line_ranges] || {}
    @spec_files              = Array(merged[:spec_files])
    @show_disabled           = merged[:show_disabled]
    @baseline_session        = merged[:baseline_session]
    @skip_heredoc_literals   = merged[:skip_heredoc_literals]
    @related_specs_heuristic = merged[:related_specs_heuristic]
    @fallback_to_full_suite  = merged[:fallback_to_full_suite]
    @quiet_children          = merged[:quiet_children]
    @quiet_children_dir      = merged[:quiet_children_dir]
  end

  def assign_validated_attributes(merged)
    @integration     = Validators::Integration.call(merged[:integration])
    @jobs            = Validators::Jobs.call(merged[:jobs])
    @fail_fast       = Validators::FailFast.call(merged[:fail_fast])
    @isolation       = Validators::Isolation.call(merged[:isolation])
    @ignore_patterns = Validators::IgnorePatterns.call(merged[:ignore_patterns])
    @hooks           = Validators::Hooks.call(merged[:hooks])
    @preload         = Validators::Preload.call(merged[:preload])
    @spec_mappings   = Validators::SpecMappings.call(merged[:spec_mappings])
    @spec_pattern    = Validators::SpecPattern.call(merged[:spec_pattern])
  end

  def assign_example_targeting(merged)
    @example_targeting          = merged[:example_targeting] ? true : false
    @example_targeting_fallback = Validators::ExampleTargetingFallback.call(merged[:example_targeting_fallback])
    @example_targeting_cache    = Validators::ExampleTargetingCache.call(merged[:example_targeting_cache])
  end
end

require_relative "config/file_loader"
require_relative "config/env_loader"
require_relative "config/sources"
require_relative "config/validators"
require_relative "config/validators/base"
require_relative "config/validators/integration"
require_relative "config/validators/isolation"
require_relative "config/validators/jobs"
require_relative "config/validators/fail_fast"
require_relative "config/validators/preload"
require_relative "config/validators/hooks"
require_relative "config/validators/ignore_patterns"
require_relative "config/validators/spec_pattern"
require_relative "config/validators/spec_mappings"
require_relative "config/validators/example_targeting_fallback"
require_relative "config/validators/example_targeting_cache"
require_relative "config/builders"
require_relative "config/builders/spec_resolver"
require_relative "config/builders/spec_selector"
