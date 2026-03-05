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

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: evilution [command] [options] [files...]"

        opts.on("-j", "--jobs N", Integer, "Number of parallel workers") { |n| @options[:jobs] = n }
        opts.on("-t", "--timeout N", Integer, "Per-mutation timeout in seconds") { |n| @options[:timeout] = n }
        opts.on("-f", "--format FORMAT", "Output format: text, json") { |f| @options[:format] = f.to_sym }
        opts.on("--diff BASE", "Only mutate code changed since BASE") { |b| @options[:diff_base] = b }
        opts.on("--min-score FLOAT", Float, "Minimum mutation score to pass") { |s| @options[:min_score] = s }
        opts.on("--no-coverage", "Disable coverage-based filtering of uncovered mutations") { @options[:coverage] = false }
        opts.on("-v", "--verbose", "Verbose output") { @options[:verbose] = true }
        opts.on("-q", "--quiet", "Suppress output") { @options[:quiet] = true }
      end

      @files = parser.parse!(argv)
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
