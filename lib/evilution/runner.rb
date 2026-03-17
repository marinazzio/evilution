# frozen_string_literal: true

require_relative "config"
require_relative "ast/parser"
require_relative "mutator/registry"
require_relative "isolation/fork"
require_relative "integration/rspec"
require_relative "reporter/json"
require_relative "reporter/cli"
require_relative "reporter/suggestion"
require_relative "diff/parser"
require_relative "diff/file_filter"
require_relative "git/changed_files"
require_relative "result/mutation_result"
require_relative "result/summary"
require_relative "baseline"
require_relative "parallel/pool"

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
      baseline_result = run_baseline(mutations)
      results, truncated = run_mutations(mutations, baseline_result)
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      summary = Result::Summary.new(results: results, duration: duration, truncated: truncated)
      output_report(summary)

      summary
    end

    private

    attr_reader :parser, :registry, :isolator

    def parse_subjects
      files = resolve_target_files
      files.flat_map { |file| parser.call(file) }
    end

    def resolve_target_files
      return config.target_files unless config.target_files.empty?

      Git::ChangedFiles.new.call
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

    def run_baseline(mutations)
      return nil unless config.baseline? && mutations.any?

      log_baseline_start
      baseline = Baseline.new(timeout: config.timeout)
      result = baseline.call(mutations)
      log_baseline_complete(result)
      result
    end

    def run_mutations(mutations, baseline_result = nil)
      if config.jobs > 1
        run_mutations_parallel(mutations, baseline_result)
      else
        run_mutations_sequential(mutations, baseline_result)
      end
    end

    def run_mutations_sequential(mutations, baseline_result = nil)
      integration = build_integration
      spec_resolver = baseline_result ? SpecResolver.new : nil
      results = []
      survived_count = 0
      truncated = false

      mutations.each_with_index do |mutation, index|
        test_command = ->(m) { integration.call(m) }
        result = isolator.call(
          mutation: mutation,
          test_command: test_command,
          timeout: config.timeout
        )
        result = neutralize_if_baseline_failed(result, baseline_result, spec_resolver)
        results << result
        survived_count += 1 if result.survived?
        log_progress(index + 1, mutations.length, result.status)

        if config.fail_fast? && survived_count >= config.fail_fast && index < mutations.length - 1
          truncated = true
          break
        end
      end

      [results, truncated]
    end

    def run_mutations_parallel(mutations, baseline_result = nil)
      integration = build_integration
      pool = Parallel::Pool.new(size: config.jobs)
      spec_resolver = baseline_result ? SpecResolver.new : nil
      results = []
      survived_count = 0
      truncated = false
      completed = 0

      mutations.each_slice(config.jobs) do |batch|
        break if truncated

        batch_results = pool.map(batch) do |mutation|
          test_command = ->(m) { integration.call(m) }
          isolator.call(mutation: mutation, test_command: test_command, timeout: config.timeout)
        end

        batch_results.each do |result|
          result = neutralize_if_baseline_failed(result, baseline_result, spec_resolver)
          results << result
          survived_count += 1 if result.survived?
          completed += 1
          log_progress(completed, mutations.length, result.status)
        end

        truncated = true if should_truncate?(survived_count, completed, mutations.length)
      end

      [results, truncated]
    end

    def neutralize_if_baseline_failed(result, baseline_result, spec_resolver)
      return result unless result.survived? && baseline_result

      spec_file = spec_resolver.call(result.mutation.file_path) || "spec"
      return result unless baseline_result.failed_spec_files.include?(spec_file)

      Result::MutationResult.new(
        mutation: result.mutation,
        status: :neutral,
        duration: result.duration,
        test_command: result.test_command
      )
    end

    def should_truncate?(survived_count, completed, total)
      config.fail_fast? && survived_count >= config.fail_fast && completed < total
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

    def log_baseline_start
      return if config.quiet || !config.text? || !$stderr.tty?

      $stderr.write("Running baseline test suite...\n")
    end

    def log_baseline_complete(result)
      return if config.quiet || !config.text? || !$stderr.tty?

      count = result.failed_spec_files.size
      $stderr.write("Baseline complete: #{count} failing spec file#{"s" unless count == 1}\n")
    end

    def log_progress(current, total, status)
      return if config.quiet || !config.text? || !$stderr.tty?

      $stderr.write("mutation #{current}/#{total} #{status}\n")
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
