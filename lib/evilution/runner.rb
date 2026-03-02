# frozen_string_literal: true

require_relative "config"
require_relative "ast/parser"
require_relative "mutator/registry"
require_relative "isolation/fork"
require_relative "integration/rspec"
require_relative "reporter/json"
require_relative "result/mutation_result"
require_relative "result/summary"

module Evilution
  class Runner
    attr_reader :config

    def initialize(config: Config.new)
      @config = config
      @parser = AST::Parser.new
      @registry = Mutator::Registry.new
      @isolator = Isolation::Fork.new
    end

    def call
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      subjects = parse_subjects
      mutations = generate_mutations(subjects)
      results = run_mutations(mutations)
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      summary = Result::Summary.new(results: results, duration: duration)
      output_report(summary) if config.format

      summary
    end

    private

    attr_reader :parser, :registry, :isolator

    def parse_subjects
      config.target_files.flat_map { |file| parser.call(file) }
    end

    def generate_mutations(subjects)
      subjects.flat_map { |subject| registry.mutations_for(subject) }
    end

    def run_mutations(mutations)
      integration = build_integration
      mutations.map do |mutation|
        test_command = ->(m) { integration.call(m) }
        isolator.call(
          mutation: mutation,
          test_command: test_command,
          timeout: config.timeout
        )
      end
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
      reporter = case config.format
                 when :json
                   Reporter::JSON.new
                 else
                   return
                 end

      output = reporter.call(summary)
      $stdout.puts(output) unless config.quiet
    end
  end
end
