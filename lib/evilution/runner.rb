# frozen_string_literal: true

require_relative "config"
require_relative "ast/parser"
require_relative "ast/inheritance_scanner"
require_relative "memory"
require_relative "mutator/registry"
require_relative "isolation/fork"
require_relative "isolation/in_process"
require_relative "integration/rspec"
require_relative "integration/minitest"
require_relative "reporter/json"
require_relative "reporter/cli"
require_relative "reporter/html"
require_relative "reporter/suggestion"
require_relative "equivalent/detector"
require_relative "git/changed_files"
require_relative "result/mutation_result"
require_relative "result/summary"
require_relative "baseline"
require_relative "cache"
require_relative "parallel/pool"
require_relative "session/store"
require_relative "ast/pattern/filter"
require_relative "temp_dir_tracker"
require_relative "disable_comment"
require_relative "ast/sorbet_sig_detector"
require_relative "rails_detector"

class Evilution::Runner
  INTEGRATIONS = {
    rspec: Evilution::Integration::RSpec,
    minitest: Evilution::Integration::Minitest
  }.freeze

  PRELOAD_CANDIDATES = [
    File.join("spec", "rails_helper.rb"),
    File.join("test", "test_helper.rb")
  ].freeze

  attr_reader :config

  def initialize(config: Evilution::Config.new, on_result: nil, hooks: nil)
    @config = config
    @on_result = on_result
    @hooks = hooks
    @parser = Evilution::AST::Parser.new
    @registry = Evilution::Mutator::Registry.default
    @cache = config.incremental? ? Evilution::Cache.new : nil
    @disable_detector = Evilution::DisableComment.new
    @disabled_ranges_cache = {}
    @sig_detector = Evilution::AST::SorbetSigDetector.new
    @sig_ranges_cache = {}
  end

  def call
    install_signal_handlers
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    subjects = parse_and_filter_subjects
    log_memory("after parse_subjects", "#{subjects.length} subjects")

    perform_preload
    log_memory("after preload") if rails_root_detected?

    baseline_result = run_baseline(subjects)

    mutations, skipped_count, disabled_mutations = generate_mutations(subjects)
    equivalent_mutations, mutations = filter_equivalent(mutations)
    release_subject_nodes(subjects)
    clear_operator_caches
    results, truncated = run_mutations(mutations, baseline_result)
    results += equivalent_mutations.map do |m|
      m.strip_sources!
      equivalent_result(m)
    end
    log_memory("after run_mutations", "#{results.length} results")

    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

    summary = Evilution::Result::Summary.new(results: results, duration: duration, truncated: truncated,
                                             skipped: skipped_count,
                                             disabled_mutations: disabled_mutations)
    output_report(summary)
    save_session(summary)

    summary
  end

  def parse_and_filter_subjects
    subjects = parse_subjects
    subjects = filter_by_descendants(subjects) if descendants_target?
    subjects = filter_by_target(subjects) if method_target?
    subjects = filter_by_line_ranges(subjects) if config.line_ranges?
    subjects
  end

  private

  attr_reader :parser, :registry, :cache, :on_result, :hooks, :disable_detector, :sig_detector

  def isolator
    @isolator ||= build_isolator
  end

  def parse_subjects
    files = resolve_target_files
    files.flat_map { |file| parser.call(file) }
  end

  def resolve_target_files
    @resolve_target_files ||= if source_glob_target?
                                resolve_source_glob
                              elsif !config.target_files.empty?
                                config.target_files
                              else
                                Evilution::Git::ChangedFiles.new.call
                              end
  end

  def source_glob_target?
    config.target&.start_with?("source:")
  end

  def descendants_target?
    config.target&.start_with?("descendants:")
  end

  def method_target?
    config.target? && !source_glob_target? && !descendants_target?
  end

  def resolve_source_glob
    pattern = config.target.delete_prefix("source:")
    files = Dir.glob(pattern)
    raise Evilution::Error, "no files found matching '#{pattern}'" if files.empty?

    files.sort
  end

  def filter_by_descendants(subjects)
    base_name = config.target.delete_prefix("descendants:")
    files = resolve_target_files
    inheritance = Evilution::AST::InheritanceScanner.call(files)
    class_names = resolve_descendant_set(base_name, inheritance)
    raise Evilution::Error, "no classes found matching '#{config.target}'" if class_names.empty?

    subjects.select { |s| class_names.include?(s.name.split(/[#.]/).first) }
  end

  def resolve_descendant_set(base_name, inheritance)
    descendants = Set.new
    known = inheritance.key?(base_name) || inheritance.value?(base_name)
    return descendants unless known

    descendants.add(base_name)
    changed = true
    while changed
      changed = false
      inheritance.each do |child, parent|
        next unless descendants.include?(parent)
        next if descendants.include?(child)

        descendants.add(child)
        changed = true
      end
    end
    descendants
  end

  def filter_by_target(subjects)
    matched = subjects.select(&target_matcher)
    raise Evilution::Error, "no method found matching '#{config.target}'" if matched.empty?

    matched
  end

  def target_matcher
    target = config.target
    if target.end_with?("*")
      prefix = target.chomp("*")
      ->(s) { s.name.split(/[#.]/).first.start_with?(prefix) }
    elsif target.end_with?("#", ".")
      prefix = target
      ->(s) { s.name.start_with?(prefix) }
    elsif target.include?("#") || target.include?(".")
      ->(s) { s.name == target }
    else
      ->(s) { s.name.start_with?("#{target}#") || s.name.start_with?("#{target}.") }
    end
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

  def generate_mutations(subjects)
    filter = build_ignore_filter
    operator_options = build_operator_options
    mutations = subjects.flat_map do |subject|
      registry.mutations_for(subject, filter: filter, operator_options: operator_options)
    end
    skipped_count = filter ? filter.skipped_count : 0

    mutations, disabled = filter_disabled(mutations)
    disabled.each(&:strip_sources!) if config.show_disabled?
    disabled_mutations = config.show_disabled? ? disabled : []

    mutations, sig_skipped = filter_sig_blocks(mutations)

    [mutations, skipped_count + disabled.length + sig_skipped, disabled_mutations]
  end

  def filter_disabled(mutations)
    enabled = []
    disabled = []

    mutations.each do |mutation|
      if mutation_disabled?(mutation)
        disabled << mutation
      else
        enabled << mutation
      end
    end

    [enabled, disabled]
  end

  def mutation_disabled?(mutation)
    ranges = disabled_ranges_for(mutation.file_path)
    ranges.any? { |range| range.cover?(mutation.line) }
  end

  def disabled_ranges_for(file_path)
    @disabled_ranges_cache[file_path] ||= begin
      source = File.read(file_path)
      @disable_detector.call(source)
    rescue SystemCallError
      []
    end
  end

  def filter_sig_blocks(mutations)
    enabled = []
    skipped = 0

    mutations.each do |mutation|
      if mutation_in_sig_block?(mutation)
        skipped += 1
      else
        enabled << mutation
      end
    end

    [enabled, skipped]
  end

  def mutation_in_sig_block?(mutation)
    ranges = sig_line_ranges_for(mutation.file_path)
    ranges.any? { |range| range.cover?(mutation.line) }
  end

  def sig_line_ranges_for(file_path)
    @sig_ranges_cache[file_path] ||= begin
      source = File.read(file_path)
      @sig_detector.line_ranges(source)
    rescue SystemCallError
      []
    end
  end

  def build_operator_options
    { skip_heredoc_literals: config.skip_heredoc_literals? }
  end

  def build_ignore_filter
    patterns = config.ignore_patterns
    return nil if patterns.nil? || patterns.empty?

    Evilution::AST::Pattern::Filter.new(patterns)
  end

  def filter_equivalent(mutations)
    Evilution::Equivalent::Detector.new.call(mutations)
  end

  def release_subject_nodes(subjects)
    subjects.each(&:release_node!)
  end

  def clear_operator_caches
    Evilution::Mutator::Base.clear_parse_cache!
  end

  def equivalent_result(mutation)
    Evilution::Result::MutationResult.new(mutation: mutation, status: :equivalent, duration: 0.0)
  end

  def run_baseline(subjects)
    return nil unless config.baseline? && subjects.any?

    log_baseline_start
    integration_class = resolve_integration_class
    baseline = Evilution::Baseline.new(timeout: config.timeout, **integration_class.baseline_options)
    result = baseline.call(subjects)
    log_baseline_complete(result)
    result
  end

  def run_mutations(mutations, baseline_result = nil)
    @progress_bar = build_progress_bar(mutations.length)
    result = if config.jobs > 1
               run_mutations_parallel(mutations, baseline_result)
             else
               run_mutations_sequential(mutations, baseline_result)
             end
    @progress_bar&.finish
    result
  end

  def run_mutations_sequential(mutations, baseline_result = nil)
    integration = build_integration
    spec_resolver = baseline_result&.failed? ? build_neutralization_resolver : nil
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
      notify_result(result, index + 1)

      if config.fail_fast? && survived_count >= config.fail_fast
        truncated = true
        break
      end
    end

    [results, truncated]
  end

  def run_mutations_parallel(mutations, baseline_result = nil)
    integration = build_integration
    pool = Evilution::Parallel::Pool.new(size: config.jobs, hooks: @hooks, item_timeout: config.timeout ? config.timeout * 2 : nil)
    worker_isolator = build_isolator
    spec_resolver = baseline_result&.failed? ? build_neutralization_resolver : nil
    state = { results: [], survived_count: 0, truncated: false, completed: 0 }

    all_worker_stats = []

    mutations.each_slice(config.jobs) do |batch|
      break if state[:truncated]

      batch_results = run_parallel_batch(batch, pool, worker_isolator, integration)
      all_worker_stats.concat(pool.worker_stats)
      process_batch(batch_results, baseline_result, spec_resolver, state)
    end

    log_worker_stats(aggregate_worker_stats(all_worker_stats))

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
      notify_result(result, state[:completed])
    end

    log_memory("after batch", "#{state[:completed]} complete")
    state[:truncated] = true if should_truncate?(state[:survived_count])
  end

  def neutralize_if_baseline_failed(result, baseline_result, spec_resolver)
    return result unless result.survived? && baseline_result && baseline_result.failed?

    if config.spec_files.any?
      neutralize = true
    else
      spec_file = spec_resolver.call(result.mutation.file_path) || neutralization_fallback_dir
      neutralize = baseline_result.failed_spec_files.include?(spec_file)
    end
    return result unless neutralize

    Evilution::Result::MutationResult.new(
      mutation: result.mutation,
      status: :neutral,
      duration: result.duration,
      test_command: result.test_command,
      child_rss_kb: result.child_rss_kb,
      memory_delta_kb: result.memory_delta_kb,
      parent_rss_kb: result.parent_rss_kb,
      error_message: result.error_message,
      error_class: result.error_class,
      error_backtrace: result.error_backtrace
    )
  end

  def compact_result(result)
    {
      status: result.status,
      duration: result.duration,
      killing_test: result.killing_test,
      test_command: result.test_command,
      child_rss_kb: result.child_rss_kb,
      memory_delta_kb: result.memory_delta_kb,
      parent_rss_kb: result.parent_rss_kb,
      error_message: result.error_message,
      error_class: result.error_class,
      error_backtrace: result.error_backtrace
    }
  end

  def rebuild_results(batch, compact_results)
    batch.zip(compact_results).map do |mutation, data|
      Evilution::Result::MutationResult.new(
        mutation: mutation,
        status: data[:status],
        duration: data[:duration],
        killing_test: data[:killing_test],
        test_command: data[:test_command],
        child_rss_kb: data[:child_rss_kb],
        memory_delta_kb: data[:memory_delta_kb],
        parent_rss_kb: data[:parent_rss_kb],
        error_message: data[:error_message],
        error_class: data[:error_class],
        error_backtrace: data[:error_backtrace]
      )
    end
  end

  def should_truncate?(survived_count)
    config.fail_fast? && survived_count >= config.fail_fast
  end

  def install_signal_handlers
    %w[INT TERM].each { |sig| install_signal_handler(sig) }
  end

  def install_signal_handler(sig)
    prev_handler = Signal.trap(sig) do
      Evilution::TempDirTracker.cleanup_all

      case prev_handler
      when Proc, Method
        prev_handler.call
      when "IGNORE"
        # Do nothing — signal is ignored
      else
        Signal.trap(sig, "DEFAULT")
        Process.kill(sig, Process.pid)
      end
    end
  end

  def build_isolator
    case resolve_isolation
    when :fork then Evilution::Isolation::Fork.new(hooks: @hooks)
    when :in_process then Evilution::Isolation::InProcess.new
    end
  end

  def resolve_isolation
    case config.isolation
    when :fork
      :fork
    when :in_process
      warn_in_process_under_rails if rails_root_detected?
      :in_process
    else # :auto
      rails_root_detected? ? :fork : :in_process
    end
  end

  def rails_root_detected?
    return @rails_root_detected if defined?(@rails_root_detected)

    @rails_root_detected = !detected_rails_root.nil?
  end

  def detected_rails_root
    return @detected_rails_root if defined?(@detected_rails_root)

    @detected_rails_root = Evilution::RailsDetector.rails_root_for_any(resolve_target_files)
  end

  def perform_preload
    return if config.preload == false
    return unless resolve_isolation == :fork

    path = resolve_preload_path
    return unless path

    prepare_load_path_for_preload
    require File.expand_path(path)
  rescue ScriptError, StandardError => e
    raise Evilution::ConfigError.new(
      "failed to preload #{path.inspect}: #{e.class}: #{e.message}",
      file: path
    )
  end

  # Preload files (e.g. spec/rails_helper.rb) typically `require 'spec_helper'`
  # which needs spec/ on $LOAD_PATH, and use `RSpec.configure` which needs
  # rspec/core loaded. The RSpec CLI normally sets this up, but evilution
  # calls Runner.run directly.
  def prepare_load_path_for_preload
    spec_dir = File.expand_path(resolve_spec_dir)
    $LOAD_PATH.unshift(spec_dir) unless $LOAD_PATH.include?(spec_dir)
    require "rspec/core" if config.integration == :rspec
  end

  def resolve_spec_dir
    root = detected_rails_root
    return File.join(root, "spec") if root

    "spec"
  end

  def resolve_preload_path
    if config.preload.is_a?(String)
      unless File.file?(config.preload)
        raise Evilution::ConfigError.new(
          "preload file not found: #{config.preload.inspect}",
          file: config.preload
        )
      end
      return config.preload
    end

    root = detected_rails_root
    return nil unless root

    PRELOAD_CANDIDATES.each do |rel|
      abs = File.join(root, rel)
      return abs if File.file?(abs)
    end
    nil
  end

  # When the user explicitly requests InProcess on a Rails project, warn once
  # per run. Rails wraps ActiveRecord transactions in
  # Thread.handle_interrupt(Exception => :never), which defers Timeout's
  # Thread#raise indefinitely — making InProcess unable to kill runaway mutants.
  def warn_in_process_under_rails
    return if config.quiet
    return if @warned_in_process_under_rails

    @warned_in_process_under_rails = true
    $stderr.write(
      "[evilution] warning: --isolation in_process is unsafe on Rails projects. " \
      "ActiveRecord wraps transactions in Thread.handle_interrupt(Exception => :never), " \
      "which swallows Timeout.timeout and can cause evilution to hang indefinitely on " \
      "mutants that introduce infinite loops. Use --isolation fork for reliable interruption.\n"
    )
  end

  def resolve_integration_class
    INTEGRATIONS.fetch(config.integration) do
      raise Evilution::Error, "unknown integration: #{config.integration}"
    end
  end

  def build_integration
    klass = resolve_integration_class
    test_files = config.spec_files.empty? ? nil : config.spec_files
    klass.new(test_files: test_files, hooks: @hooks)
  end

  def build_neutralization_resolver
    options = resolve_integration_class.baseline_options
    options[:spec_resolver] || Evilution::SpecResolver.new
  end

  def neutralization_fallback_dir
    options = resolve_integration_class.baseline_options
    options[:fallback_dir] || "spec"
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

    rss = Evilution::Memory.rss_mb
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

    $stderr.write("[verbose] #{result.mutation}: #{parts.join(", ")}\n") unless parts.empty?

    log_mutation_error(result) if result.error?
  end

  def log_mutation_error(result)
    header = "[verbose] #{result.mutation}: error"
    header += " #{result.error_class}" if result.error_class
    header += ": #{result.error_message}" if result.error_message
    $stderr.write("#{header}\n")

    Array(result.error_backtrace).first(5).each do |line|
      $stderr.write("[verbose]   #{line}\n")
    end
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

  def save_session(summary)
    return unless config.save_session?

    Evilution::Session::Store.new.save(summary)
  rescue StandardError => e
    warn "[evilution] failed to save session: #{e.message}" unless config.quiet
  end

  def log_worker_stats(stats)
    return unless config.verbose && !config.quiet && stats.any?

    stats.each do |stat|
      pct = format("%.1f", stat.utilization * 100)
      $stderr.write("[verbose] worker #{stat.pid}: #{stat.items_completed} items, utilization #{pct}%\n")
    end
  end

  def aggregate_worker_stats(stats)
    return stats if stats.empty?

    stats.group_by(&:pid).map do |pid, entries|
      Evilution::Parallel::WorkQueue::WorkerStat.new(
        pid,
        entries.sum(&:items_completed),
        entries.sum(&:busy_time),
        entries.sum(&:wall_time)
      )
    end
  end

  def notify_result(result, index)
    on_result&.call(result)
    @progress_bar&.tick(status: result.status)
    log_progress(index, result.status)
    log_mutation_diagnostics(result)
  end

  def build_progress_bar(total)
    return nil if !config.progress? || config.quiet || config.verbose || !config.text? || !$stderr.tty?

    Evilution::Reporter::ProgressBar.new(total: total, output: $stderr)
  end

  def build_reporter
    case config.format
    when :json
      Evilution::Reporter::JSON.new(integration: config.integration)
    when :text
      Evilution::Reporter::CLI.new
    when :html
      Evilution::Reporter::HTML.new(baseline: load_baseline_session, integration: config.integration)
    end
  end

  def load_baseline_session
    path = config.baseline_session
    return nil unless path

    store = Evilution::Session::Store.new
    store.load(path)
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

    Evilution::Result::MutationResult.new(
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
