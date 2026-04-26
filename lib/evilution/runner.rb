# frozen_string_literal: true

require_relative "config"
require_relative "ast/parser"
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
require_relative "git/changed_files"
require_relative "result/mutation_result"
require_relative "result/summary"
require_relative "baseline"
require_relative "cache"
require_relative "parallel/pool"
require_relative "session/store"
require_relative "temp_dir_tracker"
require_relative "rails_detector"
require_relative "parallel_db_warning"
require_relative "child_output"
require_relative "runner/subject_pipeline"
require_relative "runner/mutation_planner"
require_relative "runner/isolation_resolver"
require_relative "runner/baseline_runner"
require_relative "runner/diagnostics"
require_relative "runner/mutation_executor"
require_relative "runner/report_publisher"

class Evilution::Runner
  attr_reader :config

  def initialize(config: Evilution::Config.new, on_result: nil, hooks: nil)
    @config = config
    @on_result = on_result
    @hooks = hooks
    @parser = Evilution::AST::Parser.new
    @registry = Evilution::Mutator::Registry.default
    @cache = config.incremental? ? Evilution::Cache.new : nil
  end

  def call
    install_signal_handlers
    configure_child_output
    emit_parallel_db_warning
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    subjects = subject_pipeline.call
    log_memory("after parse_subjects", "#{subjects.length} subjects")

    perform_preload
    log_memory("after preload") if rails_root_detected?

    baseline_result = run_baseline(subjects)

    plan = mutation_planner.call(subjects)
    release_subject_nodes(subjects)
    clear_operator_caches
    results, truncated = run_mutations(plan.enabled, baseline_result)
    results += equivalent_results(plan.equivalent)
    log_memory("after run_mutations", "#{results.length} results")

    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

    summary = Evilution::Result::Summary.new(results: results, duration: duration, truncated: truncated,
                                             skipped: plan.skipped_count,
                                             disabled_mutations: plan.disabled_mutations)
    output_report(summary)
    save_session(summary)

    summary
  end

  def parse_and_filter_subjects
    subject_pipeline.call
  end

  private

  attr_reader :parser, :registry, :cache, :on_result, :hooks

  def subject_pipeline
    @subject_pipeline ||= Evilution::Runner::SubjectPipeline.new(config, parser: parser)
  end

  def mutation_planner
    @mutation_planner ||= Evilution::Runner::MutationPlanner.new(config, registry: registry)
  end

  def isolation_resolver
    @isolation_resolver ||= Evilution::Runner::IsolationResolver.new(
      config,
      target_files: -> { subject_pipeline.target_files },
      hooks: @hooks
    )
  end

  def isolator
    isolation_resolver.isolator
  end

  def rails_root_detected?
    isolation_resolver.rails_root_detected?
  end

  def perform_preload
    isolation_resolver.perform_preload
  end

  def release_subject_nodes(subjects)
    subjects.each(&:release_node!)
  end

  def clear_operator_caches
    Evilution::Mutator::Base.clear_parse_cache!
  end

  def equivalent_results(mutations)
    mutations.map do |mutation|
      mutation.strip_sources!
      Evilution::Result::MutationResult.new(mutation: mutation, status: :equivalent, duration: 0.0)
    end
  end

  def baseline_runner
    @baseline_runner ||= Evilution::Runner::BaselineRunner.new(config, hooks: @hooks)
  end

  def diagnostics
    @diagnostics ||= Evilution::Runner::Diagnostics.new(config)
  end

  def mutation_executor
    @mutation_executor ||= Evilution::Runner::MutationExecutor.new(
      config,
      isolator: isolator,
      baseline_runner: baseline_runner,
      cache: cache,
      hooks: @hooks,
      diagnostics: diagnostics,
      on_result: on_result
    )
  end

  def run_baseline(subjects)
    baseline_runner.call(subjects)
  end

  def run_mutations(mutations, baseline_result = nil)
    mutation_executor.call(mutations, baseline_result)
  end

  def emit_parallel_db_warning
    Evilution::ParallelDbWarning.warn_if_sqlite_parallel(config)
  end

  def configure_child_output
    Evilution::ChildOutput.log_dir = config.quiet_children ? config.quiet_children_dir : nil
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

  def report_publisher
    @report_publisher ||= Evilution::Runner::ReportPublisher.new(config)
  end

  def output_report(summary)
    report_publisher.publish(summary)
  end

  def save_session(summary)
    report_publisher.save_session(summary)
  end

  def log_memory(phase, context = nil)
    diagnostics.log_memory(phase, context)
  end
end
