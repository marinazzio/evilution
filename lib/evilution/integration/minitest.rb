# frozen_string_literal: true

require "stringio"
require_relative "base"
require_relative "minitest_crash_detector"
require_relative "../spec_resolver"

require_relative "../integration"

class Evilution::Integration::Minitest < Evilution::Integration::Base
  def self.baseline_runner
    lambda { |test_file|
      require "minitest"
      require "stringio"
      ::Minitest::Runnable.runnables.clear
      files = File.directory?(test_file) ? Dir.glob(File.join(test_file, "**/*_test.rb")) : [test_file]
      files.each { |f| load(File.expand_path(f)) }
      out = StringIO.new
      options = ::Minitest.process_args(["--seed", "0"])
      options[:io] = out
      reporter = ::Minitest::CompositeReporter.new
      reporter << ::Minitest::SummaryReporter.new(out, options)
      reporter.start
      ::Minitest.__run(reporter, options)
      reporter.report
      reporter.passed?
    }
  end

  def self.baseline_options
    {
      runner: baseline_runner,
      spec_resolver: Evilution::SpecResolver.new(test_dir: "test", test_suffix: "_test.rb", request_dir: "integration"),
      fallback_dir: "test"
    }
  end

  def initialize(test_files: nil, hooks: nil)
    @test_files = test_files
    @minitest_loaded = false
    @spec_resolver = Evilution::SpecResolver.new(test_dir: "test", test_suffix: "_test.rb", request_dir: "integration")
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
    command = "ruby -Itest #{files.join(" ")}"

    files.each { |f| load(File.expand_path(f)) }

    args = build_args(mutation)
    detector = reset_crash_detector
    passed = run_minitest(args, detector)

    build_minitest_result(passed, command, detector)
  rescue StandardError => e
    { passed: false, error: e.message, test_command: command }
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

    reporter.start
    ::Minitest.__run(reporter, options)
    reporter.report

    reporter.passed?
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
      { passed: false, error: "test crashes: #{detector.crash_summary}", test_command: command }
    else
      { passed: false, test_command: command }
    end
  end

  def resolve_test_files(mutation)
    return test_files if test_files

    resolved = @spec_resolver.call(mutation.file_path)
    unless resolved
      warn_unresolved_test(mutation.file_path)
      return glob_test_files
    end

    [resolved]
  end

  def glob_test_files
    files = Dir.glob("test/**/*_test.rb")
    files.empty? ? ["test"] : files
  end

  def warn_unresolved_test(file_path)
    return if @warned_files.include?(file_path)

    @warned_files << file_path
    warn "[evilution] No matching test found for #{file_path}, running full suite. " \
         "Use --spec to specify the test file."
  end
end
