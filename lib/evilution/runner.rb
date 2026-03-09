# frozen_string_literal: true

require_relative "config"
require_relative "ast/parser"
require_relative "mutator/registry"
require_relative "isolation/fork"
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
      subjects = filter_by_target(subjects) if config.target?
      subjects = filter_by_line_ranges(subjects) if config.line_ranges?
      subjects = filter_by_diff(subjects) if config.diff?
      mutations = generate_mutations(subjects)
      test_map = collect_coverage if config.coverage && config.integration == :rspec
      mutations, skipped = filter_by_coverage(mutations, test_map) if test_map
      results = run_mutations(mutations)
      results.concat(skipped) if skipped
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

    def filter_by_target(subjects)
      matched = subjects.select { |s| s.name == config.target }
      raise Error, "no method found matching '#{config.target}'" if matched.empty?

      matched
    end

    def filter_by_line_ranges(subjects)
      subjects.select do |subject|
        range = config.line_ranges[subject.file_path]
        next true unless range

        subject_start = subject.line_number
        subject_end = subject_start + subject.source.count("\n")
        subject_start <= range.last && subject_end >= range.first
      end
    end

    def filter_by_diff(subjects)
      diff_parser = Diff::Parser.new
      changed_ranges = diff_parser.parse(config.diff_base)
      Diff::FileFilter.new.filter(subjects, changed_ranges)
    end

    def generate_mutations(subjects)
      subjects.flat_map { |subject| registry.mutations_for(subject) }
    end

    def collect_coverage
      test_files = config.spec_files.empty? ? Dir.glob("spec/**/*_spec.rb") : config.spec_files
      return nil if test_files.empty?

      data = Coverage::Collector.new.call(test_files: test_files)
      Coverage::TestMap.new(data)
    end

    def filter_by_coverage(mutations, test_map)
      covered, uncovered = mutations.partition do |m|
        test_map.covered?(File.expand_path(m.file_path), m.line)
      end

      skipped = uncovered.map do |m|
        Result::MutationResult.new(mutation: m, status: :survived, duration: 0.0)
      end

      [covered, skipped]
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
        test_files = config.spec_files.empty? ? nil : config.spec_files
        Integration::RSpec.new(test_files: test_files)
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
