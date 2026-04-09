# frozen_string_literal: true

require "stringio"
require_relative "base"
require_relative "minitest_crash_detector"
require_relative "../spec_resolver"

require_relative "../integration"

class Evilution::Integration::Minitest < Evilution::Integration::Base
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
    files.each { |f| load(File.expand_path(f)) }

    command = "ruby -Itest #{files.join(" ")}"
    args = build_args(mutation)

    detector = reset_crash_detector
    passed = run_minitest(args, detector)

    build_minitest_result(passed, command, detector)
  rescue StandardError => e
    { passed: false, error: e.message, test_command: command }
  end

  def build_args(_mutation)
    ["--seed", "0", "--no-plugins"]
  end

  def reset_state
    ::Minitest::Runnable.runnables.clear
  end

  def run_minitest(args, detector)
    original_stdout = $stdout
    original_stderr = $stderr
    out = StringIO.new
    err = StringIO.new

    $stdout = out
    $stderr = err
    install_crash_detector(detector)
    ::Minitest.run(args)
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end

  def reset_crash_detector
    if @crash_detector
      @crash_detector.reset
    else
      @crash_detector = Evilution::Integration::MinitestCrashDetector.new
    end
    @crash_detector
  end

  def install_crash_detector(detector)
    ::Minitest.reporter = nil
    extensions_backup = ::Minitest.extensions.dup
    ::Minitest.extensions.clear

    original_init = ::Minitest.method(:init_plugins)
    ::Minitest.define_singleton_method(:init_plugins) do |options|
      original_init.call(options)
      ::Minitest.reporter << detector
    end
  rescue StandardError
    ::Minitest.extensions.replace(extensions_backup) if defined?(extensions_backup)
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
      return ["test"]
    end

    [resolved]
  end

  def warn_unresolved_test(file_path)
    return if @warned_files.include?(file_path)

    @warned_files << file_path
    warn "[evilution] No matching test found for #{file_path}, running full suite. " \
         "Use --spec to specify the test file."
  end
end
