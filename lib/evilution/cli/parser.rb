# frozen_string_literal: true

require "optparse"
require_relative "../version"
require_relative "parsed_args"

class Evilution::CLI::Parser
  SIMPLE_COMMANDS = {
    "version" => :version,
    "init" => :init,
    "mcp" => :mcp,
    "subjects" => :subjects
  }.freeze

  SESSION_SUBCOMMANDS = {
    "list" => :session_list,
    "show" => :session_show,
    "diff" => :session_diff,
    "gc" => :session_gc
  }.freeze

  TESTS_SUBCOMMANDS = { "list" => :tests_list }.freeze
  ENVIRONMENT_SUBCOMMANDS = { "show" => :environment_show }.freeze
  UTIL_SUBCOMMANDS = { "mutation" => :util_mutation }.freeze

  def initialize(argv, stdin: $stdin)
    @argv = argv.dup
    @stdin = stdin
    @options = {}
    @files = []
    @line_ranges = {}
    @command = :run
    @parse_error = nil
    @stdin_error = nil
  end

  def parse
    extract_command
    return build_parsed_args if @command == :parse_error

    preprocess_flags
    remaining = build_option_parser.parse!(@argv)
    @files, @line_ranges = parse_file_args(remaining)
    read_stdin_files if @options.delete(:stdin) && %i[run subjects].include?(@command)
    build_parsed_args
  end

  private

  def read_stdin_files
    if @files.any?
      @stdin_error = "--stdin cannot be combined with positional file arguments"
      return
    end

    lines = []
    @stdin.each_line do |line|
      line = line.strip
      lines << line unless line.empty?
    end
    stdin_files, stdin_ranges = parse_file_args(lines)
    @files = stdin_files
    @line_ranges = @line_ranges.merge(stdin_ranges)
  end

  def build_parsed_args
    Evilution::CLI::ParsedArgs.new(
      command: @command,
      options: @options,
      files: @files,
      line_ranges: @line_ranges,
      stdin_error: @stdin_error,
      parse_error: @parse_error
    )
  end

  def extract_command
    first = @argv.first
    if SIMPLE_COMMANDS.key?(first)
      @command = SIMPLE_COMMANDS[first]
      @argv.shift
    elsif first == "run"
      @argv.shift
    elsif first == "session"
      @argv.shift
      extract_subcommand(SESSION_SUBCOMMANDS, "session", "list, show, diff, gc")
    elsif first == "tests"
      @argv.shift
      extract_subcommand(TESTS_SUBCOMMANDS, "tests", "list")
    elsif first == "environment"
      @argv.shift
      extract_subcommand(ENVIRONMENT_SUBCOMMANDS, "environment", "show")
    elsif first == "util"
      @argv.shift
      extract_subcommand(UTIL_SUBCOMMANDS, "util", "mutation")
    end
  end

  def extract_subcommand(table, family, available)
    sub = @argv.first
    if table.key?(sub)
      @command = table[sub]
      @argv.shift
    elsif sub.nil?
      @command = :parse_error
      @parse_error = "Missing #{family} subcommand. Available subcommands: #{available}"
    else
      @command = :parse_error
      @parse_error = "Unknown #{family} subcommand: #{sub}. Available subcommands: #{available}"
      @argv.shift
    end
  end

  def preprocess_flags
    result = []
    i = 0
    while i < @argv.length
      arg = @argv[i]
      if arg == "--fail-fast"
        next_arg = @argv[i + 1]

        if next_arg && next_arg.match?(/\A-?\d+\z/)
          @options[:fail_fast] = next_arg
          i += 2
        else
          result << arg
          i += 1
        end
      elsif arg.start_with?("--fail-fast=")
        @options[:fail_fast] = arg.delete_prefix("--fail-fast=")
        i += 1
      else
        result << arg
        i += 1
      end
    end
    @argv = result
  end

  def build_option_parser
    OptionParser.new do |opts|
      opts.banner = "Usage: evilution [command] [options] [files...]"
      opts.version = Evilution::VERSION
      add_separators(opts)
      add_options(opts)
    end
  end

  def add_separators(opts)
    opts.separator ""
    opts.separator "Line-range targeting: lib/foo.rb:15-30, lib/foo.rb:15, lib/foo.rb:15-"
    opts.separator ""
    opts.separator "Commands: run (default), init, session {list,show,diff,gc}, subjects, tests {list},"
    opts.separator "         util {mutation}, environment {show}, mcp, version"
    opts.separator ""
    opts.separator "Options:"
  end

  def add_options(opts)
    add_core_options(opts)
    add_filter_options(opts)
    add_flag_options(opts)
    add_session_options(opts)
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
    add_extra_flag_options(opts)
  end

  def add_extra_flag_options(opts)
    opts.on("--skip-heredoc-literals", "Skip all string literal mutations inside heredocs") { @options[:skip_heredoc_literals] = true }
    opts.on("--related-specs-heuristic", "Append related request/integration/feature/system specs for includes() mutations") do
      @options[:related_specs_heuristic] = true
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

  def parse_file_args(raw_args)
    files = []
    ranges = {}

    raw_args.each do |arg|
      file, range_str = arg.split(":", 2)
      files << file
      next unless range_str

      ranges[file] = parse_line_range(range_str)
    end

    [files, ranges]
  end

  def parse_line_range(str)
    if str.include?("-")
      start_str, end_str = str.split("-", 2)
      start_line = Integer(start_str)
      end_line = end_str.empty? ? Float::INFINITY : Integer(end_str)
      start_line..end_line
    else
      line = Integer(str)
      line..line
    end
  end

  def expand_spec_dir(dir)
    unless File.directory?(dir)
      warn("Error: #{dir} is not a directory")
      return
    end

    specs = Dir.glob(File.join(dir, "**/*_spec.rb"))
    @options[:spec_files] = Array(@options[:spec_files]) + specs
  end
end
