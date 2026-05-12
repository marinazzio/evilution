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
    ::Minitest::Runnable.runnables.clear
    baseline_test_files(test_file).each { |f| load(File.expand_path(f)) }
    run_baseline_minitest
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

    files.each { |f| load(File.expand_path(f)) }

    args = build_args(mutation)
    detector = reset_crash_detector
    passed = run_minitest(args, detector)

    build_minitest_result(passed, command, detector)
  rescue StandardError => e
    { passed: false, error: e.message, test_command: command }
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
    reporter << ::Minitest::SummaryReporter.new(out, options)
    reporter << detector

    self.class.initialize_minitest_state(reporter, options)
    reporter.start
    dispatch_minitest_suites(reporter, options)
    reporter.report

    reporter.passed?
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
