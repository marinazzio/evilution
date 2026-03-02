# frozen_string_literal: true

require_relative "config"
require_relative "ast/parser"
require_relative "mutator/registry"
require_relative "isolation/fork"
require_relative "parallel/pool"
require_relative "integration/rspec"
require_relative "reporter/json"
require_relative "reporter/cli"
require_relative "reporter/suggestion"
require_relative "coverage/collector"
require_relative "coverage/test_map"
require_relative "diff/parser"
require_relative "diff/file_filter"
require_relative "result/mutation_result"
require_relative "result/summary"

module Evilution
  class Runner
    attr_reader :config

    def initialize(config: Config.new)
      @config = config
      @parser = AST::Parser.new
      @registry = Mutator::Registry.default
      @isolator = Isolation::Fork.new
    end

    def call
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      subjects = parse_subjects
      subjects = filter_by_diff(subjects) if config.diff?
      mutations = generate_mutations(subjects)
      results = run_mutations(mutations)
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      summary = Result::Summary.new(results: results, duration: duration)
      output_report(summary)

      summary
    end

    private

    attr_reader :parser, :registry, :isolator

    def parse_subjects
      config.target_files.flat_map { |file| parser.call(file) }
    end

    def filter_by_diff(subjects)
      diff_parser = Diff::Parser.new
      changed_ranges = diff_parser.parse(config.diff_base)
      Diff::FileFilter.new.filter(subjects, changed_ranges)
    end

    def generate_mutations(subjects)
      subjects.flat_map { |subject| registry.mutations_for(subject) }
    end

    def run_mutations(mutations)
      integration = build_integration

      if config.jobs > 1 && mutations.size > 1
        run_parallel(mutations, integration)
      else
        run_sequential(mutations, integration)
      end
    end

    def run_sequential(mutations, integration)
      mutations.map do |mutation|
        test_command = ->(m) { integration.call(m) }
        isolator.call(
          mutation: mutation,
          test_command: test_command,
          timeout: config.timeout
        )
      end
    end

    def run_parallel(mutations, integration)
      pool = Parallel::Pool.new(jobs: config.jobs)
      test_command_builder = ->(_mutation) { ->(m) { integration.call(m) } }
      pool.call(mutations: mutations, test_command_builder: test_command_builder, timeout: config.timeout)
    end

    def build_integration
      case config.integration
      when :rspec
        Integration::RSpec.new
      else
        raise Error, "unknown integration: #{config.integration}"
      end
    end

    def output_report(summary)
      reporter = build_reporter
      return unless reporter

      output = reporter.call(summary)
      $stdout.puts(output) unless config.quiet
    end

    def build_reporter
      case config.format
      when :json
        Reporter::JSON.new
      when :text
        Reporter::CLI.new
      end
    end
  end
end
