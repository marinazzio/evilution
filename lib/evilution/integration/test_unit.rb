# frozen_string_literal: true

require_relative "base"
require_relative "test_unit_crash_detector"
require_relative "loading/test_load_path"
require_relative "../spec_resolver"
require_relative "../spec_selector"

require_relative "../integration"

# Test::Unit integration. Decomposed under lib/evilution/integration/test_unit/
# mirroring the RSpec integration's layout. This class is the orchestrator:
# it wires the framework loader, dispatcher, subject-class registry,
# test-file resolver, and result builder. The class is registered under
# Evilution::Runner::INTEGRATIONS[:test_unit] and reachable via the
# `--integration test-unit` CLI flag.
class Evilution::Integration::TestUnit < Evilution::Integration::Base
  def self.baseline_runner
    ->(test_file) { run_baseline_test_file(test_file) }
  end

  # SpecResolver tuned for the dominant Test::Unit layout: tests live under
  # test/, named with the _test.rb suffix (the same convention Minitest uses).
  # Rails plugins on the test-unit gem (e.g. kaminari-core) follow this layout.
  # The test/test_<name>.rb prefix-style convention is rare enough in practice
  # that we defer support to a follow-up if a project surfaces needing it.
  def self.spec_resolver
    Evilution::SpecResolver.new(test_dir: "test", test_suffix: "_test.rb", request_dir: "integration")
  end

  def self.baseline_options
    {
      runner: baseline_runner,
      spec_resolver: spec_resolver,
      fallback_dir: "test"
    }
  end

  def self.run_baseline_test_file(test_file)
    require_relative "test_unit/framework_loader"
    require_relative "test_unit/subject_class_registry"
    require_relative "test_unit/dispatcher"
    FrameworkLoader.new.call
    files = baseline_test_files(test_file)
    Evilution::Integration::Loading::TestLoadPath.add!(files)
    new_classes = SubjectClassRegistry.newly_loaded do
      files.each { |f| load(File.expand_path(f)) }
    end
    Dispatcher.call(new_classes, name: "evilution baseline").passed?
  end

  def self.baseline_test_files(test_file)
    File.directory?(test_file) ? Dir.glob(File.join(test_file, "**/*_test.rb")) : [test_file]
  end

  def initialize(test_files: nil, hooks: nil, fallback_to_full_suite: false, spec_selector: nil)
    require_relative "test_unit/framework_loader"
    require_relative "test_unit/subject_class_registry"
    require_relative "test_unit/dispatcher"
    require_relative "test_unit/test_file_resolver"
    require_relative "test_unit/result_builder"
    @framework_loader = FrameworkLoader.new
    @file_resolver = TestFileResolver.new(
      test_files: test_files,
      spec_selector: spec_selector || Evilution::SpecSelector.new(spec_resolver: self.class.spec_resolver),
      fallback_to_full_suite: fallback_to_full_suite
    )
    @crash_detector = nil
    super(hooks: hooks)
  end

  private

  def ensure_framework_loaded
    return if @framework_loader.loaded?

    fire_hook(:setup_integration_pre, integration: :test_unit)
    @framework_loader.call
    fire_hook(:setup_integration_post, integration: :test_unit)
  end

  def run_tests(mutation)
    ensure_framework_loaded
    reset_state
    files = @file_resolver.call(mutation.file_path)
    return ResultBuilder.unresolved(mutation.file_path) if files.nil?

    command = "ruby -Itest #{files.join(" ")}"
    execute_test_unit(files, command)
  rescue StandardError => e
    { passed: false, error: e.message, test_command: command }
  end

  def execute_test_unit(files, command)
    new_classes = load_test_classes(files)
    return ResultBuilder.no_tests_ran(command) if Dispatcher.test_method_count(new_classes).zero?

    detector = reset_crash_detector
    result = Dispatcher.call(new_classes, name: "evilution-mutation")
    result.faults.each { |fault| detector.record(fault) }
    ResultBuilder.call(passed: result.passed?, command: command, detector: detector)
  end

  def load_test_classes(files)
    Evilution::Integration::Loading::TestLoadPath.add!(files)
    SubjectClassRegistry.newly_loaded do
      files.each { |f| load(File.expand_path(f, Evilution.project_base_dir)) }
    end
  end

  # Test::Unit has no public registry-clear analogous to
  # Minitest::Runnable.runnables.clear. SubjectClassRegistry's newly_loaded
  # block scopes each dispatch to classes loaded in *this* round, so stale
  # classes from prior mutations sit dormant on ObjectSpace without polluting
  # the run. #reset_state stays as a contract no-op for parity with Minitest.
  def reset_state
    # no-op — see comment above
  end

  def build_args(_mutation)
    []
  end

  def reset_crash_detector
    if @crash_detector
      @crash_detector.reset
    else
      @crash_detector = Evilution::Integration::TestUnitCrashDetector.new
    end
    @crash_detector
  end
end
