# frozen_string_literal: true

require "English"
require "fileutils"
require "timeout"
require "tmpdir"
require_relative "../memory"
require_relative "../result/mutation_result"

require_relative "../isolation"

class Evilution::Isolation::InProcess
  # Raised into the run when its time is up. A SignalException, because the
  # timeout has to end the whole test run and a test framework rescues nearly
  # everything a test raises, Timeout::Error included: it would record one
  # failed test and go on to the next, which may reach the same endless loop
  # with no timer left to stop it. Minitest, Test::Unit and RSpec all let a
  # SignalException through.
  #
  # Not an Interrupt, though it is one of those: tooling that handles the
  # user's Ctrl-C (maxitest) rescues Interrupt and skips every test from then
  # on, for the rest of the process.
  class Expired < SignalException
    def initialize(_message = nil)
      super("SIGALRM")
    end
  end

  @null_out = File.open(File::NULL, "w")
  @null_err = File.open(File::NULL, "w")

  class << self
    attr_reader :null_out, :null_err

    # The mutation this process is testing, remembered so that a process dying
    # in the middle of it can say which one it was. Ruby runs no `ensure` on
    # some deaths (a stack overflow through `const_missing`, under the usual
    # stack limit), so the mutation is still on record when the at_exit hook
    # asks. The process is recorded with it: a process the tests fork inherits
    # both the record and the hook, and its death is not this run's.
    #
    # The error stream is recorded as well, as it is before the mutation is
    # tested: `$stderr` is the null stream while it is, and on such a death
    # nothing puts it back.
    def watch(mutation)
      @watched = [Process.pid, mutation, $stderr]
      return if @death_hook_installed

      @death_hook_installed = true
      at_exit { report_death($ERROR_INFO) }
    end

    def unwatch
      @watched = nil
    end

    def watched
      pid, mutation, = @watched
      mutation if pid == Process.pid
    end

    def report_death(error, stream: nil)
      mutation = watched
      return if mutation.nil? || error.nil?
      return if error.is_a?(SystemExit) || error.is_a?(SignalException)

      stream ||= @watched.last
      stream.puts(
        "[evilution] the run died while testing a mutation under in-process isolation: " \
        "#{mutation} (#{error.class}: #{error.message}). " \
        "In-process isolation cannot contain a mutation that takes the Ruby process down; " \
        "re-run with --isolation fork."
      )
    end
  end

  def call(mutation:, test_command:, timeout:)
    self.class.watch(mutation)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rss_before = Evilution::Memory.rss_kb
    sandbox_dir = Dir.mktmpdir("evilution-run")
    result = execute_with_timeout(mutation, test_command, timeout, sandbox_dir)
    rss_after = Evilution::Memory.rss_kb
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    delta = compute_memory_delta(rss_before, rss_after, result)

    build_mutation_result(mutation, result, duration, rss_before, rss_after, delta)
  ensure
    self.class.unwatch
    FileUtils.rm_rf(sandbox_dir) if sandbox_dir
  end

  private

  # The Dir.chdir block is inside the Timeout.timeout block so that a
  # timeout raised mid-call still unwinds through Dir.chdir's ensure
  # and restores the parent CWD before the rescue clause runs. The sandbox
  # contains any relative-path writes from path-relativizing mutations
  # (EV-wqxu / GH #1278). Evilution.with_isolated_worker signals the rest of
  # evilution (SpecResolver/SpecSelector/SpecAstCache/MutationApplier/
  # SourceEvaluator/Integration) to anchor project-relative paths to
  # PROJECT_ROOT for the duration of the call.
  def execute_with_timeout(mutation, test_command, timeout, sandbox_dir)
    result = Timeout.timeout(timeout, Expired) do
      Evilution.with_isolated_worker do
        Dir.chdir(sandbox_dir) do
          suppress_output { test_command.call(mutation) }
        end
      end
    end
    { timeout: false }.merge(result)
  rescue Expired
    { timeout: true }
  rescue ScriptError, StandardError => e
    failure_result(e, e.message)
  rescue SignalException, SystemExit
    raise
  rescue Exception => e # rubocop:disable Lint/RescueException -- turned into this mutation's result
    crash_result(e)
  end

  # An exception outside StandardError that no test framework held back: a
  # stack overflow that unwound, most likely. Left alone it would end the run.
  # Leaving the test run that way, after the mutated source loaded, is what a
  # test that crashes does, and counts the same.
  def crash_result(error)
    message = "#{error.class}: #{error.message}"
    return failure_result(error, message) unless Evilution.died_running_tests?(error)

    failure_result(error, "test run ended by #{message}").merge(test_crashed: true)
  end

  def failure_result(error, message)
    {
      timeout: false,
      passed: false,
      error: message,
      error_class: error.class.name,
      error_backtrace: Array(error.backtrace).first(5)
    }
  end

  def suppress_output
    saved_stdout = $stdout
    saved_stderr = $stderr
    $stdout = self.class.null_out
    $stderr = self.class.null_err
    yield
  ensure
    $stdout = saved_stdout
    $stderr = saved_stderr
  end

  def compute_memory_delta(rss_before, rss_after, result)
    return nil if result[:timeout]
    return nil unless rss_before && rss_after

    rss_after - rss_before
  end

  def classify_status(result)
    return :timeout if result[:timeout]
    return :killed if result[:test_crashed] || result[:load_crashed]
    return :unresolved if result[:unresolved]
    return :error if result[:error]
    return :survived if result[:passed]

    :killed
  end

  def build_mutation_result(mutation, result, duration, rss_before, rss_after, memory_delta_kb)
    status = classify_status(result)

    Evilution::Result::MutationResult.new(
      mutation: mutation,
      status: status,
      duration: duration,
      test_command: result[:test_command],
      memory: Evilution::Result::MemoryStats.from_fields(
        child_rss_kb: rss_after,
        memory_delta_kb: memory_delta_kb,
        parent_rss_kb: rss_before
      ),
      error: Evilution::Result::ErrorInfo.from_fields(
        message: result[:error],
        klass: result[:error_class],
        backtrace: result[:error_backtrace]
      ),
      known_failures_only: result[:known_failures_only]
    )
  end
end
