# frozen_string_literal: true

require "json"
require "optparse"
require_relative "version"
require_relative "config"
require_relative "runner"

module Evilution
  class CLI
    def initialize(argv, stdin: $stdin)
      @options = {}
      @command = :run
      @stdin = stdin
      argv = argv.dup
      argv = extract_command(argv)
      argv = preprocess_flags(argv)
      raw_args = build_option_parser.parse!(argv)
      @files, @line_ranges = parse_file_args(raw_args)
      read_stdin_files if @options.delete(:stdin) && @command == :run
    end

    def call
      case @command
      when :version
        $stdout.puts(VERSION)
        0
      when :init
        run_init
      when :mcp
        run_mcp
      when :session_list
        run_session_list
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
      when "mcp"
        @command = :mcp
        argv.shift
      when "session"
        argv.shift
        extract_session_subcommand(argv)
      when "run"
        argv.shift
      end
      argv
    end

    def extract_session_subcommand(argv)
      case argv.first
      when "list"
        @command = :session_list
        argv.shift
      end
    end

    def preprocess_flags(argv)
      result = []
      i = 0
      while i < argv.length
        arg = argv[i]
        if arg == "--fail-fast"
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
        opts.version = VERSION
        add_separators(opts)
        add_options(opts)
      end
    end

    def add_separators(opts)
      opts.separator ""
      opts.separator "Line-range targeting: lib/foo.rb:15-30, lib/foo.rb:15, lib/foo.rb:15-"
      opts.separator ""
      opts.separator "Commands: run (default), init, session list, mcp, version"
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
      opts.on("--target METHOD", "Only mutate the named method (e.g. Foo::Bar#calculate)") { |m| @options[:target] = m }
    end

    def add_flag_options(opts)
      opts.on("--fail-fast", "Stop after N surviving mutants " \
                             "(default: disabled; if provided without N, uses 1; use --fail-fast=N)") { @options[:fail_fast] ||= 1 }
      opts.on("--no-baseline", "Skip baseline test suite check") { @options[:baseline] = false }
      opts.on("--incremental", "Cache killed/timeout results; skip re-running them on unchanged files") { @options[:incremental] = true }
      opts.on("--isolation STRATEGY", "Isolation: auto, fork, in_process (default: auto)") { |s| @options[:isolation] = s }
      opts.on("--stdin", "Read target file paths from stdin (one per line)") { @options[:stdin] = true }
      opts.on("--suggest-tests", "Generate concrete RSpec test code in suggestions") { @options[:suggest_tests] = true }
      opts.on("--save-session", "Save session results to .evilution/results/") { @options[:save_session] = true }
      opts.on("-v", "--verbose", "Verbose output") { @options[:verbose] = true }
      opts.on("-q", "--quiet", "Suppress output") { @options[:quiet] = true }
    end

    def add_session_options(opts)
      opts.on("--results-dir DIR", "Session results directory") { |d| @options[:results_dir] = d }
      opts.on("--limit N", Integer, "Show only the N most recent sessions") { |n| @options[:limit] = n }
      opts.on("--since DATE", "Show sessions since DATE (YYYY-MM-DD)") { |d| @options[:since] = d }
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

    def run_mcp
      require_relative "mcp/server"
      server = MCP::Server.build
      transport = ::MCP::Server::Transports::StdioTransport.new(server)
      transport.open
      0
    end

    def read_stdin_files
      @stdin_error = "--stdin cannot be combined with positional file arguments" unless @files.empty?
      return if @stdin_error

      lines = []
      @stdin.each_line do |line|
        line = line.strip
        lines << line unless line.empty?
      end
      stdin_files, stdin_ranges = parse_file_args(lines)
      @files = stdin_files
      @line_ranges = @line_ranges.merge(stdin_ranges)
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

    def run_session_list
      require_relative "session/store"

      store_opts = {}
      store_opts[:results_dir] = @options[:results_dir] if @options[:results_dir]
      store = Session::Store.new(**store_opts)
      sessions = store.list
      sessions = filter_sessions(sessions)

      if sessions.empty?
        $stdout.puts("No sessions found")
        return 0
      end

      if @options[:format] == :json
        $stdout.puts(JSON.pretty_generate(sessions.map { |s| session_to_hash(s) }))
      else
        print_session_table(sessions)
      end

      0
    end

    def filter_sessions(sessions)
      if @options[:since]
        cutoff = Time.parse(@options[:since])
        sessions = sessions.select { |s| Time.parse(s[:timestamp]) >= cutoff }
      end
      sessions = sessions.first(@options[:limit]) if @options[:limit]
      sessions
    end

    def session_to_hash(session)
      {
        "timestamp" => session[:timestamp],
        "total" => session[:total],
        "killed" => session[:killed],
        "survived" => session[:survived],
        "score" => session[:score],
        "duration" => session[:duration],
        "file" => session[:file]
      }
    end

    def print_session_table(sessions)
      header = "Timestamp                       Total Killed  Surv.    Score Duration"
      $stdout.puts(header)
      $stdout.puts("-" * header.length)
      sessions.each { |s| print_session_row(s) }
    end

    def print_session_row(session)
      $stdout.puts(
        format(
          "%-30<ts>s %6<total>d %6<killed>d %6<surv>d %7.2<score>f%% %7.1<dur>fs",
          ts: session[:timestamp], total: session[:total], killed: session[:killed],
          surv: session[:survived], score: session[:score] * 100, dur: session[:duration]
        )
      )
    end

    def run_mutations
      raise ConfigError, @stdin_error if @stdin_error

      file_options = Config.file_options
      config = Config.new(**@options, target_files: @files, line_ranges: @line_ranges)
      runner = Runner.new(config: config)
      summary = runner.call
      summary.success?(min_score: config.min_score) ? 0 : 1
    rescue Error => e
      if json_format?(config, file_options)
        $stdout.puts(JSON.generate(error_payload(e)))
      else
        warn("Error: #{e.message}")
      end
      2
    end

    def json_format?(config, file_options)
      return config.json? if config

      format = @options[:format] || (file_options && file_options[:format])
      format && format.to_sym == :json
    end

    def error_payload(error)
      error_type = case error
                   when ConfigError then "config_error"
                   when ParseError then "parse_error"
                   else "runtime_error"
                   end

      payload = { type: error_type, message: error.message }
      payload[:file] = error.file if error.file
      { error: payload }
    end
  end
end
