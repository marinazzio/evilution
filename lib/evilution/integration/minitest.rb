# frozen_string_literal: true

require "stringio"
require_relative "base"
require_relative "minitest_crash_detector"
require_relative "../spec_resolver"
require_relative "../spec_selector"

require_relative "../integration"

class Evilution::Integration::Minitest < Evilution::Integration::Base
  def self.baseline_runner
    ->(test_file) { run_baseline_test_file(test_file) }
  end

  def self.run_baseline_test_file(test_file)
    require "minitest"
    require "stringio"
    stub_autorun!
    ::Minitest::Runnable.runnables.clear
    baseline_test_files(test_file).each { |f| load(File.expand_path(f)) }
    run_baseline_minitest
  end

  # User helpers that `require "minitest/autorun"` install an at_exit handler
  # calling `Minitest.run(ARGV)`. At evilution process exit ARGV still holds
  # evilution flags (--integration, --spec, ...) and Minitest's option parser
  # prints a misleading "invalid option" banner. Stubbing autorun before user
  # code loads prevents the handler from ever being installed.
  def self.stub_autorun!
    location = ::Minitest.singleton_class.instance_method(:autorun).source_location
    return if location && location.first == __FILE__

    ::Minitest.define_singleton_method(:autorun) { nil }
  end

  def self.baseline_test_files(test_file)
    File.directory?(test_file) ? Dir.glob(File.join(test_file, "**/*_test.rb")) : [test_file]
  end

  def self.run_baseline_minitest
    out = StringIO.new
    options = ::Minitest.process_args(["--seed", "0"])
    options[:io] = out
    reporter = ::Minitest::CompositeReporter.new
    reporter << ::Minitest::SummaryReporter.new(out, options)
    initialize_minitest_state(reporter, options)
    reporter.start
    dispatch_minitest_suites(reporter, options)
    reporter.report
    reporter.passed?
  end

  # Mirror Minitest.run's preamble: seed setup + plugin init. Without seeding
  # Minitest.seed before dispatching suites, Minitest 5.x raises
  # `TypeError: no implicit conversion of nil into Integer` from
  # Minitest::Test.runnable_methods calling `srand(Minitest.seed)` on nil.
  # init_plugins also needs Minitest.reporter set first because some plugins
  # (pride) read it during init.
  def self.initialize_minitest_state(reporter, options)
    ::Minitest.seed = options[:seed]
    srand(::Minitest.seed) if ::Minitest.seed

    ::Minitest.reporter = reporter
    ::Minitest.init_plugins(options) if ::Minitest.respond_to?(:init_plugins)
    ::Minitest.reporter = nil
  end

  # Dispatch to the version-appropriate suite runner. Minitest 6 removed
  # ::Minitest.__run; the equivalent public entry point is run_all_suites.
  # Minitest 5.x still exposes __run.
  def self.dispatch_minitest_suites(reporter, options)
    if ::Minitest.respond_to?(:run_all_suites)
      ::Minitest.run_all_suites(reporter, options)
    elsif ::Minitest.respond_to?(:__run)
      ::Minitest.__run(reporter, options)
    else
      raise Evilution::Error,
            "Minitest #{::Minitest::VERSION} has neither run_all_suites nor __run"
    end
  end

  def self.baseline_options
    {
      runner: baseline_runner,
      spec_resolver: Evilution::SpecResolver.new(test_dir: "test", test_suffix: "_test.rb", request_dir: "integration"),
      fallback_dir: "test"
    }
  end

  def initialize(test_files: nil, hooks: nil, fallback_to_full_suite: false, spec_selector: nil)
    @test_files = test_files
    @minitest_loaded = false
    @spec_selector = spec_selector || Evilution::SpecSelector.new(
      spec_resolver: Evilution::SpecResolver.new(test_dir: "test", test_suffix: "_test.rb", request_dir: "integration")
    )
    @fallback_to_full_suite = fallback_to_full_suite
    @crash_detector = nil
    @warned_files = Set.new
    super(hooks: hooks)
  end

  private

  attr_reader :test_files

  def ensure_framework_loaded
    return if @minitest_loaded

    fire_hook(:setup_integration_pre, integration: :minitest)
    require "minitest"
    self.class.stub_autorun!
    @minitest_loaded = true
    fire_hook(:setup_integration_post, integration: :minitest)
  rescue LoadError => e
    raise Evilution::Error, "minitest is required but not available: #{e.message}"
  end

  def run_tests(mutation)
    reset_state
    files = resolve_test_files(mutation)
    return unresolved_result(mutation) if files.nil?

    command = "ruby -Itest #{files.join(" ")}"
    execute_minitest(mutation, files, command)
  rescue StandardError => e
    { passed: false, error: e.message, test_command: command }
  end

  def execute_minitest(mutation, files, command)
    files.each { |f| load(File.expand_path(f)) }

    detector = reset_crash_detector
    run = run_minitest(build_args(mutation), detector)

    return no_tests_ran_result(command) if run[:count].zero?

    build_minitest_result(run[:passed], command, detector)
  end

  # Zero dispatched test methods means the run carries no signal — the result
  # is neither survived nor killed. Most common cause: the project's tests use
  # a framework other than Minitest (e.g. the test-unit gem, whose
  # Test::Unit::TestCase classes are not Minitest::Runnable), or --spec points
  # at a file that registers no Minitest suite. Report :error so the score is
  # not silently inflated to 0% with every mutation marked survived.
  def no_tests_ran_result(command)
    {
      passed: false,
      error: "no Minitest tests executed (0 test methods ran) — the resolved " \
             "spec registered no Minitest suite. Check --integration/--spec; " \
             "the project may use a non-Minitest framework (e.g. test-unit).",
      error_class: "Evilution::Error",
      test_command: command
    }
  end

  def unresolved_result(mutation)
    {
      passed: false,
      unresolved: true,
      error: "no matching test resolved for #{mutation.file_path}",
      test_command: "ruby -Itest (skipped: no test resolved for #{mutation.file_path})"
    }
  end

  def build_args(_mutation)
    ["--seed", "0"]
  end

  def reset_state
    ::Minitest::Runnable.runnables.clear
  end

  def run_minitest(args, detector)
    out = StringIO.new
    options = ::Minitest.process_args(args)
    options[:io] = out

    reporter = ::Minitest::CompositeReporter.new
    reporter << detector

    self.class.initialize_minitest_state(reporter, options)
    summary = attach_summary_reporter(reporter, out, options)
    reporter.start
    dispatch_minitest_suites(reporter, options)
    reporter.report

    { passed: summary.passed?, count: minitest_method_count }
  end

  # Add evilution's own SummaryReporter to the composite AFTER plugin init,
  # and read the run's verdict from it rather than from reporter.passed?.
  #
  # A target test helper that calls Minitest::Reporters.use! makes
  # init_plugins replace the composite's reporters with minitest-reporters'
  # DelegateReporter, which delegates to a process-global reporter created
  # once by use!. That global reporter is never reset between runs, so under
  # in_process isolation — where one process runs every mutation in sequence
  # — its failures accumulate: reporter.passed? would report false for every
  # mutation after the first genuine kill, false-killing real survivors and
  # inflating the score. A fresh SummaryReporter attached here survives
  # plugin init (init_plugins already ran) and sees only the current run,
  # giving an isolation-correct pass/fail.
  def attach_summary_reporter(reporter, out, options)
    summary = ::Minitest::SummaryReporter.new(out, options)
    reporter << summary
    summary
  end

  # Count dispatched test methods from the runnable registry, not a reporter.
  # A project test helper that calls Minitest::Reporters.use! swaps the
  # composite's reporters during init_plugins, evicting evilution's
  # SummaryReporter — a reporter-based count then reads 0 even on a real run.
  # The runnable registry is immune to reporter plugins. Must run after
  # initialize_minitest_state: runnable_methods calls srand(Minitest.seed).
  def minitest_method_count
    ::Minitest::Runnable.runnables.sum { |r| r.runnable_methods.size }
  end

  def dispatch_minitest_suites(reporter, options)
    self.class.dispatch_minitest_suites(reporter, options)
  end

  def reset_crash_detector
    if @crash_detector
      @crash_detector.reset
    else
      @crash_detector = Evilution::Integration::MinitestCrashDetector.new
    end
    @crash_detector
  end

  def build_minitest_result(passed, command, detector)
    if passed
      { passed: true, test_command: command }
    elsif detector.only_crashes?
      classes = detector.unique_crash_classes
      {
        passed: false,
        test_crashed: true,
        error: "test crashes: #{detector.crash_summary}",
        error_class: (classes.first if classes.length == 1),
        test_command: command
      }
    else
      { passed: false, test_command: command }
    end
  end

  def resolve_test_files(mutation)
    return test_files if test_files

    resolved = Array(@spec_selector.call(mutation.file_path))
    if resolved.empty?
      warn_unresolved_test(mutation.file_path)
      return @fallback_to_full_suite ? glob_test_files : nil
    end

    resolved
  end

  def glob_test_files
    files = Dir.glob("test/**/*_test.rb")
    files.empty? ? ["test"] : files
  end

  def warn_unresolved_test(file_path)
    return if @warned_files.include?(file_path)

    @warned_files << file_path
    action = @fallback_to_full_suite ? "running full suite" : "marking mutation unresolved"
    warn "[evilution] No matching test found for #{file_path}, #{action}. " \
         "Use --spec to specify the test file."
  end
end
