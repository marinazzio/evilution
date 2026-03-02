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
      when "run"
        argv.shift
      end

      parser = OptionParser.new do |opts|
        opts.on("-j", "--jobs N", Integer) { |n| @options[:jobs] = n }
        opts.on("-t", "--timeout N", Integer) { |n| @options[:timeout] = n }
        opts.on("-f", "--format FORMAT") { |f| @options[:format] = f.to_sym }
        opts.on("--diff BASE") { |b| @options[:diff_base] = b }
        opts.on("--min-score FLOAT", Float) { |s| @options[:min_score] = s }
        opts.on("--no-coverage") { @options[:coverage] = false }
        opts.on("-v", "--verbose") { @options[:verbose] = true }
        opts.on("-q", "--quiet") { @options[:quiet] = true }
      end

      @files = parser.parse!(argv)
    end

    def call
      case @command
      when :version
        $stdout.puts(VERSION)
        0
      when :run
        config = Config.new(**@options, target_files: @files)
        runner = Runner.new(config: config)
        summary = runner.call
        summary.success?(min_score: config.min_score) ? 0 : 1
      end
    end
  end
end
