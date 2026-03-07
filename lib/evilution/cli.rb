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
      argv = warn_removed_flags(argv)
      @files = build_option_parser.parse!(argv)
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

    def warn_removed_flags(argv)
      result = []
      i = 0
      while i < argv.length
        arg = argv[i]
        if %w[--jobs -j].include?(arg)
          warn("Warning: --jobs is no longer supported and will be ignored.")
          next_arg = argv[i + 1]
          i += next_arg&.match?(/\A-?\d+\z/) ? 2 : 1
        elsif arg.start_with?("--jobs=") || arg.match?(/\A-j-?\d+\z/)
          warn("Warning: --jobs is no longer supported and will be ignored.")
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

        opts.separator ""
        opts.separator "Commands:"
        opts.separator "    run        Execute mutation testing (default)"
        opts.separator "    init       Generate .evilution.yml config file"
        opts.separator "    version    Print version string"
        opts.separator ""
        opts.separator "Options:"

        opts.on("-t", "--timeout N", Integer, "Per-mutation timeout in seconds") { |n| @options[:timeout] = n }
        opts.on("-f", "--format FORMAT", "Output format: text, json") { |f| @options[:format] = f.to_sym }
        opts.on("--diff BASE", "Only mutate code changed since BASE") { |b| @options[:diff_base] = b }
        opts.on("--min-score FLOAT", Float, "Minimum mutation score to pass") { |s| @options[:min_score] = s }
        opts.on("--no-coverage", "Disable coverage-based filtering of uncovered mutations") { @options[:coverage] = false }
        opts.on("-v", "--verbose", "Verbose output") { @options[:verbose] = true }
        opts.on("-q", "--quiet", "Suppress output") { @options[:quiet] = true }
      end
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

    def run_mutations
      config = Config.new(**@options, target_files: @files)
      runner = Runner.new(config: config)
      summary = runner.call
      summary.success?(min_score: config.min_score) ? 0 : 1
    rescue Error => e
      warn("Error: #{e.message}")
      2
    end
  end
end
