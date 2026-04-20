# frozen_string_literal: true

require "optparse"
require_relative "../../version"
require_relative "file_args"

class Evilution::CLI::Parser::OptionsBuilder
  def self.build(options)
    new(options).build
  end

  def initialize(options)
    @options = options
  end

  def build
    OptionParser.new do |opts|
      opts.banner = "Usage: evilution [command] [options] [files...]"
      opts.version = Evilution::VERSION
      add_separators(opts)
      add_core_options(opts)
      add_filter_options(opts)
      add_flag_options(opts)
      add_extra_flag_options(opts)
      add_session_options(opts)
    end
  end

  private

  def add_separators(opts)
    opts.separator ""
    opts.separator "Line-range targeting: lib/foo.rb:15-30, lib/foo.rb:15, lib/foo.rb:15-"
    opts.separator ""
    opts.separator "Commands: run (default), init, session {list,show,diff,gc}, subjects, tests {list},"
    opts.separator "         util {mutation}, environment {show}, mcp, version"
    opts.separator ""
    opts.separator "Options:"
  end

  def add_core_options(opts)
    opts.on("-j", "--jobs N", Integer, "Number of parallel workers (default: 1)") { |n| @options[:jobs] = n }
    opts.on("-t", "--timeout N", Integer, "Per-mutation timeout in seconds") { |n| @options[:timeout] = n }
    opts.on("-f", "--format FORMAT", "Output format: text, json, html") { |f| @options[:format] = f.to_sym }
  end

  def add_filter_options(opts)
    opts.on("--min-score FLOAT", Float, "Minimum mutation score to pass") { |s| @options[:min_score] = s }
    opts.on("--spec FILES", Array, "Spec files to run (comma-separated)") { |f| @options[:spec_files] = f }
    opts.on("--spec-dir DIR", "Include all specs in DIR") { |d| expand_spec_dir(d) }
    opts.on("--spec-pattern GLOB",
            "Restrict resolved spec candidates to files matching GLOB") { |p| @options[:spec_pattern] = p }
    opts.on("--no-example-targeting",
            "Disable per-mutation example targeting (run all examples in resolved spec files)") do
      @options[:example_targeting] = false
    end
    opts.on("--example-targeting-fallback MODE", %w[full_file unresolved],
            "Fallback when example targeting finds no match: full_file (default) or unresolved") do |m|
      @options[:example_targeting_fallback] = m
    end
    opts.on("--target EXPR",
            "Filter: method (Foo#bar), type (Foo#/Foo.), namespace (Foo*),",
            "class (Foo), glob (source:**/*.rb), hierarchy (descendants:Foo)") do |m|
      @options[:target] = m
    end
  end

  def add_flag_options(opts)
    opts.on("--fail-fast", "Stop after N surviving mutants " \
                           "(default: disabled; if provided without N, uses 1; use --fail-fast=N)") { @options[:fail_fast] ||= 1 }
    opts.on("--no-baseline", "Skip baseline test suite check") { @options[:baseline] = false }
    opts.on("--incremental", "Cache killed/timeout results; skip re-running them on unchanged files") { @options[:incremental] = true }
    opts.on("--integration NAME", "Test integration: rspec, minitest (default: rspec)") { |i| @options[:integration] = i }
    opts.on("--isolation STRATEGY", "Isolation: auto, fork, in_process (default: auto)") { |s| @options[:isolation] = s }
    opts.on("--preload FILE", "Preload FILE in the parent process before forking " \
                              "(default: auto-detect spec/rails_helper.rb for Rails projects)") { |f| @options[:preload] = f }
    opts.on("--no-preload", "Disable parent-process preload even for Rails projects") { @options[:preload] = false }
    opts.on("--stdin", "Read target file paths from stdin (one per line)") { @options[:stdin] = true }
    opts.on("--suggest-tests", "Generate concrete test code in suggestions (RSpec or Minitest)") { @options[:suggest_tests] = true }
    opts.on("--no-progress", "Disable progress bar") { @options[:progress] = false }
  end

  def add_extra_flag_options(opts)
    opts.on("--skip-heredoc-literals", "Skip all string literal mutations inside heredocs") { @options[:skip_heredoc_literals] = true }
    opts.on("--related-specs-heuristic", "Append related request/integration/feature/system specs for includes() mutations") do
      @options[:related_specs_heuristic] = true
    end
    opts.on("--fallback-full-suite", "Run the whole test suite when no matching spec/test resolves " \
                                     "for a mutation (default: mark the mutation :unresolved and skip)") do
      @options[:fallback_to_full_suite] = true
    end
    opts.on("--show-disabled", "Report mutations skipped by # evilution:disable") { @options[:show_disabled] = true }
    opts.on("--baseline-session PATH", "Compare against a baseline session in HTML report") { |p| @options[:baseline_session] = p }
    opts.on("--save-session", "Save session results to .evilution/results/") { @options[:save_session] = true }
    opts.on("-e", "--eval CODE", "Evaluate code snippet (for util mutation)") { |c| @options[:eval] = c }
    opts.on("-v", "--verbose", "Verbose output") { @options[:verbose] = true }
    opts.on("-q", "--quiet", "Suppress output") { @options[:quiet] = true }
  end

  def add_session_options(opts)
    opts.on("--results-dir DIR", "Session results directory") { |d| @options[:results_dir] = d }
    opts.on("--limit N", Integer, "Show only the N most recent sessions") { |n| @options[:limit] = n }
    opts.on("--since DATE", "Show sessions since DATE (YYYY-MM-DD)") { |d| @options[:since] = d }
    opts.on("--older-than DURATION", "Delete sessions older than DURATION (e.g., 30d, 24h, 1w)") do |d|
      @options[:older_than] = d
    end
  end

  def expand_spec_dir(dir)
    specs = Evilution::CLI::Parser::FileArgs.expand_spec_dir(dir)
    @options[:spec_files] = Array(@options[:spec_files]) + specs
  end
end
