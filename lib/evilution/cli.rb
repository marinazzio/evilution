# frozen_string_literal: true

require "optparse"
require_relative "version"
require_relative "config"
require_relative "runner"

module Evilution
  class CLI
    def initialize(argv)
      @options = {}
      @command = :run
      argv = argv.dup
      argv = extract_command(argv)
      argv = preprocess_flags(argv)
      raw_args = build_option_parser.parse!(argv)
      @files, @line_ranges = parse_file_args(raw_args)
    end

    def call
      case @command
      when :version
        $stdout.puts(VERSION)
        0
      when :init
        run_init
      when :run
        run_mutations
      end
    end

    private

    def extract_command(argv)
      case argv.first
      when "version"
        @command = :version
        argv.shift
      when "init"
        @command = :init
        argv.shift
      when "run"
        argv.shift
      end
      argv
    end

    def preprocess_flags(argv)
      result = []
      i = 0
      while i < argv.length
        arg = argv[i]
        if %w[--jobs -j].include?(arg)
          warn("Warning: --jobs is no longer supported and will be ignored.")
          next_arg = argv[i + 1]
          numeric_next = next_arg && next_arg.match?(/\A-?\d+\z/)
          i += numeric_next ? 2 : 1
        elsif arg.start_with?("--jobs=") || arg.match?(/\A-j-?\d+\z/)
          warn("Warning: --jobs is no longer supported and will be ignored.")
          i += 1
        elsif arg == "--fail-fast"
          next_arg = argv[i + 1]

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
      result
    end

    def build_option_parser
      OptionParser.new do |opts|
        opts.banner = "Usage: evilution [command] [options] [files...]"
        add_separators(opts)
        add_options(opts)
      end
    end

    def add_separators(opts)
      opts.separator ""
      opts.separator "Line-range targeting: lib/foo.rb:15-30, lib/foo.rb:15, lib/foo.rb:15-"
      opts.separator ""
      opts.separator "Commands: run (default), init, version"
      opts.separator ""
      opts.separator "Options:"
    end

    def add_options(opts)
      opts.on("-t", "--timeout N", Integer, "Per-mutation timeout in seconds") { |n| @options[:timeout] = n }
      opts.on("-f", "--format FORMAT", "Output format: text, json") { |f| @options[:format] = f.to_sym }
      opts.on("--diff BASE", "DEPRECATED: Use line-range targeting instead") do |b|
        warn("Warning: --diff is deprecated and will be removed in a future version. " \
             "Use line-range targeting instead: evilution run lib/foo.rb:15-30")
        @options[:diff_base] = b
      end
      opts.on("--min-score FLOAT", Float, "Minimum mutation score to pass") { |s| @options[:min_score] = s }
      opts.on("--spec FILES", Array, "Spec files to run (comma-separated)") { |f| @options[:spec_files] = f }
      opts.on("--target METHOD", "Only mutate the named method (e.g. Foo::Bar#calculate)") { |m| @options[:target] = m }
      opts.on("--no-coverage", "DEPRECATED: Has no effect and will be removed in a future version") do
        warn("Warning: --no-coverage is deprecated, currently has no effect, and will be removed in a future version.")
        @options[:coverage] = false
      end
      opts.on("--fail-fast", "Stop after N surviving mutants " \
                             "(default: disabled; if provided without N, uses 1; use --fail-fast=N)") { @options[:fail_fast] ||= 1 }
      opts.on("-v", "--verbose", "Verbose output") { @options[:verbose] = true }
      opts.on("-q", "--quiet", "Suppress output") { @options[:quiet] = true }
    end

    def run_init
      path = ".evilution.yml"
      if File.exist?(path)
        warn("#{path} already exists")
        return 1
      end

      File.write(path, Config.default_template)
      $stdout.puts("Created #{path}")
      0
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

    def run_mutations
      config = Config.new(**@options, target_files: @files, line_ranges: @line_ranges)
      runner = Runner.new(config: config)
      summary = runner.call
      summary.success?(min_score: config.min_score) ? 0 : 1
    rescue Error => e
      warn("Error: #{e.message}")
      2
    end
  end
end
