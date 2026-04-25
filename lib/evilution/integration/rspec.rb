# frozen_string_literal: true

require "stringio"
require_relative "base"
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
    super(hooks: hooks)
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

    args = ["--format", "progress", "--no-color", "--order", "defined", *targets]
    command = "rspec #{args.join(" ")}"

    reset_examples
    detector = @crash_detector_lifecycle.current
    snapshot = @state_guard.snapshot
    begin
      status = ::RSpec::Core::Runner.run(args, StringIO.new, StringIO.new)
      @result_builder.from_run(status, command, detector)
    rescue StandardError => e
      { passed: false, error: e.message, test_command: command }
    ensure
      @state_guard.release(snapshot)
    end
  end

  def reset_examples
    ::RSpec.respond_to?(:clear_examples) ? ::RSpec.clear_examples : ::RSpec.reset
  end
end

require_relative "rspec/framework_loader"
require_relative "rspec/test_file_resolver"
require_relative "rspec/unresolved_spec_warner"
require_relative "rspec/example_filter_applier"
require_relative "rspec/crash_detector_lifecycle"
require_relative "rspec/result_builder"
require_relative "rspec/baseline_runner"
require_relative "rspec/state_guard"
