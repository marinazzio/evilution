# frozen_string_literal: true

require "stringio"
require_relative "base"
require_relative "known_failures"
require_relative "stop_policy"
require_relative "../spec_resolver"
require_relative "../spec_selector"
require_relative "../related_spec_heuristic"

require_relative "../integration"

class Evilution::Integration::RSpec < Evilution::Integration::Base
  def self.baseline_runner
    BaselineRunner.new
  end

  def self.baseline_options
    { runner: baseline_runner }
  end

  def initialize(
    test_files: nil,
    hooks: nil,
    related_specs_heuristic: false,
    fallback_to_full_suite: false,
    spec_selector: nil,
    example_filter: nil,
    known_failures: [],
    stop_on_kill: false,
    example_durations: {},
    framework_loader: FrameworkLoader.new,
    test_file_resolver: nil,
    example_filter_applier: nil,
    crash_detector_lifecycle: CrashDetectorLifecycle.new,
    result_builder: ResultBuilder.new,
    state_guard: StateGuard.new
  )
    @framework_loader = framework_loader
    @test_file_resolver = test_file_resolver || TestFileResolver.new(
      test_files: test_files,
      spec_selector: spec_selector || Evilution::SpecSelector.new,
      related_spec_heuristic: Evilution::RelatedSpecHeuristic.new,
      related_specs_heuristic_enabled: related_specs_heuristic,
      fallback_to_full_suite: fallback_to_full_suite,
      warner: UnresolvedSpecWarner.new
    )
    @example_filter_applier = example_filter_applier || build_example_filter_applier(example_filter)
    @crash_detector_lifecycle = crash_detector_lifecycle
    @result_builder = result_builder
    @state_guard = state_guard
    @known_failures = Evilution::Integration::KnownFailures.new(known_failures)
    @stop_policy = Evilution::Integration::StopPolicy.new(enabled: stop_on_kill, known_failures: @known_failures)
    @killer_first = KillerFirst.new(stop_on_kill: stop_on_kill, durations: example_durations)
    @target_resolver = TargetResolver.new
    super(hooks: hooks)
  end

  # Taken by the runs that follow, until the next call (see KillerFirst).
  def prioritize(test_ids)
    @killer_first.prioritize(test_ids)
  end

  # One mutation per source file is enough: every mutation in a file shares
  # its source and resolves to the same spec files.
  def warm_targeting(mutations)
    mutations.uniq(&:file_path).each do |mutation|
      files = @test_file_resolver.call(mutation, warn: false)
      @example_filter_applier.warm(mutation, files) unless files.nil?
    end
  end

  # Whether no example of the spec files this mutation would run executes the
  # line it sits on (see Evilution::CoverageExampleFilter#uncovered?). Asked in
  # the parent, ahead of the run, like #warm_targeting.
  def uncovered?(mutation)
    files = @test_file_resolver.call(mutation, warn: false)
    return false if files.nil?

    @example_filter_applier.uncovered?(mutation, files)
  end

  private

  def build_example_filter_applier(example_filter)
    return ExampleFilterApplier::Identity.new unless example_filter

    ExampleFilterApplier::Custom.new(example_filter)
  end

  def ensure_framework_loaded
    return if @framework_loader.loaded?

    fire_hook(:setup_integration_pre, integration: :rspec)
    @framework_loader.call
    fire_hook(:setup_integration_post, integration: :rspec)
  end

  def run_tests(mutation)
    files = @test_file_resolver.call(mutation)
    return @result_builder.unresolved(mutation) if files.nil?

    targets = @example_filter_applier.call(mutation, files)
    return @result_builder.unresolved_example(mutation) if targets.nil?

    result = run_targets(targets, ordered: @killer_first.applies?)
    return result unless confirm?(result, targets, files)

    confirm_run(result, files)
  end

  # A survivor's confirming run is left in the defined order, so its verdict
  # comes from the file as it always ran. The examples both runs ran count.
  def confirm_run(first, files)
    started = monotonic_now
    confirmed = run_targets(files)
    examples_run = [first[:examples_run], confirmed[:examples_run]].compact
    confirmed = confirmed.merge(examples_run: examples_run.sum) unless examples_run.empty?
    confirmed.merge(timings: { confirmation: monotonic_now - started })
  end

  # Targeting runs a subset of the examples in a spec file, chosen by name. A
  # mutation that subset does not catch looks like a survivor whether or not the
  # rest of the file would have caught it, and a survivor nobody can reproduce
  # is worse than a missed kill: it sends the reader to write a test that is
  # already there (EV-f8h3 / GH #1624).
  #
  # So a survivor is re-run against the whole resolved file, and that run is the
  # one reported. Only survivors pay for it, and only where the subset was
  # actually narrower than the file.
  #
  # The same goes for a subset in which nothing failed but examples that were
  # failing before any mutation ran: that is no verdict either, and the rest of
  # the file may hold one.
  def confirm?(result, targets, files)
    (result[:passed] || result[:known_failures_only]) && targets != files
  end

  # The command reported is the run in the defined order: it is what a reader
  # can run to reproduce the verdict, and the killer-first ordering exists
  # only inside evilution.
  def run_targets(targets, ordered: false)
    files = @target_resolver.call(targets)
    command = "rspec #{run_args("defined", files).join(" ")}"
    args = ordered ? run_args(ExampleOrder::NAME, files) : run_args("defined", files)

    reset_examples
    execute_run(args, command, ordered: ordered)
  end

  def run_args(order, files)
    ["--format", "progress", "--no-color", "--order", order.to_s, *files]
  end

  def execute_run(args, command, ordered: false)
    snapshot = @state_guard.snapshot
    quit_before = ::RSpec.world.wants_to_quit
    detector = nil
    begin
      out = StringIO.new
      err = StringIO.new
      claim_rspec_streams(out, err)
      detector = @crash_detector_lifecycle.register(@stop_policy)
      status = @killer_first.during(ordered) { ::RSpec::Core::Runner.run(args, err, out) }
      build_result(status, command, detector)
    rescue StandardError => e
      { passed: false, error: e.message, test_command: command }
    ensure
      lower_own_stop(quit_before, detector)
      @state_guard.release(snapshot)
    end
  end

  # Which example killed, if one did, and how many ran: the parent runs the
  # killer first for the mutations next to this one, and the count is what
  # the ordering saves.
  def build_result(status, command, detector)
    flagged = known_failures_only?(status)
    result = @result_builder.from_run(status, command, detector, examples_loaded:, known_failures_only: flagged)
    @result_builder.with_run_facts(result, killing_example: detector.killing_id,
                                           examples_run: ExampleIds.executed_count(::RSpec.world))
  end

  # A run that stops at its kill raises RSpec.world.wants_to_quit, and left up
  # it would make the next RSpec::Core::Runner.run in this process return a
  # failure status without running anything -- a false kill. So the flag goes
  # back to what it was, but only when the crash detector raised it: raised by
  # anything else, such as RSpec's own handler on the user's first Ctrl-C, it
  # stays up even if the run later stopped at a kill, so the next Ctrl-C still
  # exits.
  def lower_own_stop(quit_before, detector)
    return if detector.nil?

    ::RSpec.world.wants_to_quit = quit_before if detector.raised_quit?
  end

  # RSpec redirects its own output to the streams it is handed only when the
  # stream its configuration already holds is the current `$stdout`. In-process
  # isolation swaps `$stdout` for a null IO around every mutation, and a
  # configuration built before that swap — which is what `--preload` produces,
  # since the project's spec_helper calls RSpec.configure — still holds the real
  # stdout. The two no longer match, RSpec keeps its own stream, and the run's
  # output lands on the real stdout ahead of the report (EV-m6xc / GH #1627).
  #
  # So the streams are claimed outright rather than offered. The ivars are
  # written directly because `output_stream=` is guarded once a reporter exists.
  # The reporter and its formatters are dropped along with them: both hold the
  # stream they were built with, so leaving them in place would keep writing
  # wherever the host pointed. StateGuard snapshots all four ivars and puts the
  # host's back afterwards.
  def claim_rspec_streams(out, err)
    config = ::RSpec.configuration
    config.instance_variable_set(:@output_stream, out)
    config.instance_variable_set(:@error_stream, err)
    %i[@reporter @formatter_loader].each do |ivar|
      config.remove_instance_variable(ivar) if config.instance_variable_defined?(ivar)
    end
  end

  # Count of examples loaded into RSpec.world by this run. Used to distinguish
  # "test failed → mutation killed" (positive count, nonzero status) from
  # "spec file failed to load / RSpec returned nonzero with nothing observed"
  # (zero count, nonzero status). The latter must NOT be classified as killed
  # — silently counting it would inflate scores with mutations no example
  # actually saw (EV-720r).
  def examples_loaded
    world = ::RSpec.world
    return nil unless world.respond_to?(:example_count)

    world.example_count
  rescue StandardError
    nil
  end

  # Whether the run failed on nothing but examples the baseline already saw
  # failing. Decided here, in the process that ran them: the names of every
  # failing example need not travel back, only the answer.
  def known_failures_only?(status)
    return false if status.zero? || @known_failures.empty?

    @known_failures.only?(ExampleIds.failed(::RSpec.world))
  end

  def reset_examples
    ::RSpec.respond_to?(:clear_examples) ? ::RSpec.clear_examples : ::RSpec.reset
  end
end

require_relative "rspec/framework_loader"
require_relative "rspec/example_ids"
require_relative "rspec/example_order"
require_relative "rspec/killer_first"
require_relative "rspec/target_resolver"
require_relative "rspec/test_file_resolver"
require_relative "rspec/unresolved_spec_warner"
require_relative "rspec/example_filter_applier"
require_relative "rspec/crash_detector_lifecycle"
require_relative "rspec/result_builder"
require_relative "rspec/baseline_runner"
require_relative "rspec/state_guard"
