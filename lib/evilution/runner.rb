# frozen_string_literal: true

require_relative "config"
require_relative "ast/parser"
require_relative "memory"
require_relative "mutator/registry"
require_relative "isolation/fork"
require_relative "isolation/in_process"
require_relative "integration/rspec"
require_relative "reporter/json"
require_relative "reporter/cli"
require_relative "reporter/html"
require_relative "reporter/suggestion"
require_relative "diff/parser"
require_relative "diff/file_filter"
require_relative "git/changed_files"
require_relative "result/mutation_result"
require_relative "result/summary"
require_relative "baseline"
require_relative "cache"
require_relative "parallel/pool"

module Evilution
  class Runner
    attr_reader :config

    def initialize(config: Config.new)
      @config = config
      @parser = AST::Parser.new
      @registry = Mutator::Registry.default
      @isolator = build_isolator
      @cache = config.incremental? ? Cache.new : nil
    end

    def call
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      subjects = parse_subjects
      subjects = filter_by_target(subjects) if config.target?
      subjects = filter_by_line_ranges(subjects) if config.line_ranges?
      subjects = filter_by_diff(subjects) if config.diff?
      log_memory("after parse_subjects", "#{subjects.length} subjects")

      baseline_result = run_baseline(subjects)

      mutations = generate_mutations(subjects)
      equivalent_mutations, mutations = filter_equivalent(mutations)
      release_subject_nodes(subjects)
      results, truncated = run_mutations(mutations, baseline_result)
      results += equivalent_mutations.map { |m| equivalent_result(m) }
      log_memory("after run_mutations", "#{results.length} results")

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      summary = Result::Summary.new(results: results, duration: duration, truncated: truncated)
      output_report(summary)

      summary
    end

    private

    attr_reader :parser, :registry, :isolator, :cache

    def parse_subjects
      files = resolve_target_files
      files.flat_map { |file| parser.call(file) }
    end

    def resolve_target_files
      return config.target_files unless config.target_files.empty?

      Git::ChangedFiles.new.call
    end

    def filter_by_target(subjects)
      matched = if config.target.include?("#")
                  subjects.select { |s| s.name == config.target }
                else
                  subjects.select { |s| s.name.start_with?("#{config.target}#") }
                end
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
      subjects.flat_map do |subject|
        registry.mutations_for(subject)
      end
    end

    def filter_equivalent(mutations)
      Equivalent::Detector.new.call(mutations)
    end

    def release_subject_nodes(subjects)
      subjects.each(&:release_node!)
    end

    def equivalent_result(mutation)
      Result::MutationResult.new(mutation: mutation, status: :equivalent, duration: 0.0)
    end

    def run_baseline(subjects)
      return nil unless config.baseline? && subjects.any?

      log_baseline_start
      baseline = Baseline.new(timeout: config.timeout)
      result = baseline.call(subjects)
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
      spec_resolver = baseline_result&.failed? ? SpecResolver.new : nil
      results = []
      survived_count = 0
      truncated = false

      mutations.each_with_index do |mutation, index|
        result = execute_or_fetch(mutation) do
          test_command = ->(m) { integration.call(m) }
          isolator.call(mutation: mutation, test_command: test_command, timeout: config.timeout)
        end
        mutation.strip_sources!
        result = neutralize_if_baseline_failed(result, baseline_result, spec_resolver)
        results << result
        survived_count += 1 if result.survived?
        log_progress(index + 1, result.status)
        log_mutation_diagnostics(result)

        if config.fail_fast? && survived_count >= config.fail_fast
          truncated = true
          break
        end
      end

      [results, truncated]
    end

    def run_mutations_parallel(mutations, baseline_result = nil)
      integration = build_integration
      pool = Parallel::Pool.new(size: config.jobs)
      worker_isolator = Isolation::InProcess.new
      spec_resolver = baseline_result&.failed? ? SpecResolver.new : nil
      state = { results: [], survived_count: 0, truncated: false, completed: 0 }

      mutations.each_slice(config.jobs) do |batch|
        break if state[:truncated]

        batch_results = run_parallel_batch(batch, pool, worker_isolator, integration)
        process_batch(batch_results, baseline_result, spec_resolver, state)
      end

      [state[:results], state[:truncated]]
    end

    def run_parallel_batch(batch, pool, worker_isolator, integration)
      uncached_indices, cached_results = partition_cached(batch)
      worker_results = run_uncached_workers(batch, uncached_indices, pool, worker_isolator, integration)
      compact_results = merge_parallel_results(batch, uncached_indices, cached_results, worker_results)
      batch.each(&:strip_sources!)
      batch_results = rebuild_results(batch, compact_results)
      batch_results.each { |r| store_cached_result(r.mutation, r) }
      batch_results
    end

    def run_uncached_workers(batch, uncached_indices, pool, worker_isolator, integration)
      return [] if uncached_indices.empty?

      uncached = uncached_indices.map { |i| batch[i] }
      pool.map(uncached) do |mutation|
        test_command = ->(m) { integration.call(m) }
        result = worker_isolator.call(mutation: mutation, test_command: test_command, timeout: config.timeout)
        compact_result(result)
      end
    end

    def process_batch(batch_results, baseline_result, spec_resolver, state)
      batch_results.each do |result|
        result = neutralize_if_baseline_failed(result, baseline_result, spec_resolver)
        state[:results] << result
        state[:survived_count] += 1 if result.survived?
        state[:completed] += 1
        log_progress(state[:completed], result.status)
        log_mutation_diagnostics(result)
      end

      log_memory("after batch", "#{state[:completed]} complete")
      state[:truncated] = true if should_truncate?(state[:survived_count])
    end

    def neutralize_if_baseline_failed(result, baseline_result, spec_resolver)
      return result unless result.survived? && baseline_result && baseline_result.failed?

      if config.spec_files.any?
        neutralize = true
      else
        spec_file = spec_resolver.call(result.mutation.file_path) || "spec"
        neutralize = baseline_result.failed_spec_files.include?(spec_file)
      end
      return result unless neutralize

      Result::MutationResult.new(
        mutation: result.mutation,
        status: :neutral,
        duration: result.duration,
        test_command: result.test_command,
        child_rss_kb: result.child_rss_kb,
        memory_delta_kb: result.memory_delta_kb
      )
    end

    def compact_result(result)
      {
        status: result.status,
        duration: result.duration,
        killing_test: result.killing_test,
        test_command: result.test_command,
        child_rss_kb: result.child_rss_kb,
        memory_delta_kb: result.memory_delta_kb
      }
    end

    def rebuild_results(batch, compact_results)
      batch.zip(compact_results).map do |mutation, data|
        Result::MutationResult.new(
          mutation: mutation,
          status: data[:status],
          duration: data[:duration],
          killing_test: data[:killing_test],
          test_command: data[:test_command],
          child_rss_kb: data[:child_rss_kb],
          memory_delta_kb: data[:memory_delta_kb]
        )
      end
    end

    def should_truncate?(survived_count)
      config.fail_fast? && survived_count >= config.fail_fast
    end

    def build_isolator
      case resolve_isolation
      when :fork then Isolation::Fork.new
      when :in_process then Isolation::InProcess.new
      end
    end

    def resolve_isolation
      return :fork if config.isolation == :fork

      :in_process
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
      return if config.quiet

      if config.html?
        path = "evilution-report.html"
        File.write(path, output)
        warn "HTML report written to #{path}"
      else
        $stdout.puts(output)
      end
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

    def log_progress(current, status)
      return if config.quiet || !config.text? || !$stderr.tty?

      $stderr.write("mutation #{current} #{status}\n")
    end

    def log_memory(phase, context = nil)
      return unless config.verbose && !config.quiet

      rss = Memory.rss_mb
      return unless rss

      gc = gc_stats_string
      msg = format("[memory] %<phase>s: %<rss>.1f MB", phase: phase, rss: rss)
      context = [context, gc].compact.join(", ")
      msg += " (#{context})" unless context.empty?
      $stderr.write("#{msg}\n")
    end

    def log_mutation_diagnostics(result)
      return unless config.verbose && !config.quiet

      parts = []
      parts << format("child_rss: %<mb>.1f MB", mb: result.child_rss_kb / 1024.0) if result.child_rss_kb

      if result.memory_delta_kb
        sign = result.memory_delta_kb.negative? ? "" : "+"
        parts << format("delta: %<sign>s%<mb>.1f MB", sign: sign, mb: result.memory_delta_kb / 1024.0)
      end

      parts << gc_stats_string

      return if parts.empty?

      $stderr.write("[verbose] #{result.mutation}: #{parts.join(", ")}\n")
    end

    def gc_stats_string
      stats = GC.stat
      format(
        "heap_live_slots: %<live>d, allocated: %<alloc>d, freed: %<freed>d",
        live: stats[:heap_live_slots],
        alloc: stats[:total_allocated_objects],
        freed: stats[:total_freed_objects]
      )
    end

    def build_reporter
      case config.format
      when :json
        Reporter::JSON.new
      when :text
        Reporter::CLI.new
      when :html
        Reporter::HTML.new
      end
    end

    def partition_cached(batch)
      uncached_indices = []
      cached_results = {}

      batch.each_with_index do |mutation, i|
        cached = fetch_cached_result(mutation)
        if cached
          cached_results[i] = compact_result(cached)
        else
          uncached_indices << i
        end
      end

      [uncached_indices, cached_results]
    end

    def merge_parallel_results(batch, uncached_indices, cached_results, worker_results)
      result_map = cached_results.dup
      uncached_indices.each_with_index { |batch_idx, worker_idx| result_map[batch_idx] = worker_results[worker_idx] }
      batch.each_index.map { |i| result_map[i] }
    end

    def execute_or_fetch(mutation)
      cached = fetch_cached_result(mutation)
      return cached if cached

      result = yield
      store_cached_result(mutation, result)
      result
    end

    def fetch_cached_result(mutation)
      return nil unless cache

      data = cache.fetch(mutation)
      return nil unless data
      return nil unless %i[killed timeout].include?(data[:status])

      Result::MutationResult.new(
        mutation: mutation,
        status: data[:status],
        duration: data[:duration],
        killing_test: data[:killing_test],
        test_command: data[:test_command]
      )
    end

    def store_cached_result(mutation, result)
      return unless cache
      return unless result.killed? || result.timeout?

      cache.store(mutation,
                  status: result.status,
                  duration: result.duration,
                  killing_test: result.killing_test,
                  test_command: result.test_command)
    end
  end
end
