# frozen_string_literal: true

require_relative "spec_resolver"
require_relative "process_cleanup"
require_relative "diagnostic"

class Evilution::Baseline
  Result = Struct.new(:failed_spec_files, :duration, :failures) do
    def initialize(failed_spec_files:, duration:, failures: [])
      super
      freeze
    end

    def failed?
      !failed_spec_files.empty?
    end

    # Every example known to have failed before any mutation ran.
    def failed_example_ids
      failures.flat_map(&:failed_ids).to_set
    end
  end

  # spec_selector: the object `run` resolves with (integration layout plus
  # spec_mappings / spec_pattern), returning every spec covering a source.
  # Without one, the bare spec_resolver is used. spec_resolver also supplies
  # the best-guess hint for an unresolved source.
  #
  # fallback_to_full_suite: whether an unresolved source runs the whole
  # fallback_dir. When false its mutations are reported unresolved, so the
  # baseline skips it rather than running -- and often timing out on -- the
  # entire test directory.
  def initialize(spec_resolver: Evilution::SpecResolver.new, timeout: 30, runner: nil,
                 fallback_dir: "spec", test_files: nil, spec_selector: nil, fallback_to_full_suite: true)
    @spec_resolver = spec_resolver
    @timeout = timeout
    @runner = runner
    @fallback_dir = fallback_dir
    @test_files = test_files
    @spec_selector = spec_selector
    @fallback_to_full_suite = fallback_to_full_suite
  end

  def call(subjects)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    failures = baseline_spec_files(subjects).filter_map { |spec_file| check_spec_file(spec_file) }

    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    Result.new(failed_spec_files: failures.to_set(&:spec_file), duration: duration, failures: failures)
  end

  def run_spec_file(spec_file)
    check_spec_file(spec_file).nil?
  end

  # nil when the spec file passed, otherwise why it did not. Anything that
  # stops the baseline from getting an answer counts as failing, and is
  # recorded as the reason.
  def check_spec_file(spec_file)
    raise Evilution::Error, "no baseline runner configured" unless @runner

    read_io, write_io = IO.pipe
    pid = fork_spec_runner(spec_file, read_io, write_io)
    write_io.close
    read_result(read_io, pid, spec_file)
  rescue Evilution::Error
    raise
  rescue StandardError => e
    warned(SpecFailure.new(spec_file: spec_file, error: "#{e.class}: #{e.message}"))
  ensure
    read_io.close if read_io
    write_io.close if write_io
  end

  def fork_spec_runner(spec_file, read_io, write_io)
    runner = @runner
    Process.fork do
      read_io.close
      $stdout.reopen(File::NULL, "w")
      $stderr.reopen(File::NULL, "w")

      report = child_report(runner, spec_file)
      Marshal.dump(report, write_io)
      write_io.close
      exit!(report[:passed] ? 0 : 1)
    end
  end

  GRACE_PERIOD = 0.5

  def read_result(read_io, pid, spec_file)
    return timed_out(pid, spec_file) unless read_io.wait_readable(@timeout)

    data = read_io.read
    _, status = Process.wait2(pid)
    return warned(SpecFailure.new(spec_file: spec_file, error: unreported_error(status))) if data.empty?

    report = Marshal.load(data)
    report[:passed] ? nil : warned(SpecFailure.from_report(spec_file, report))
  end

  def warn_timeout(spec_file)
    Evilution::Diagnostic.warn("[evilution] Baseline for #{spec_file} timed out after #{@timeout}s; treating it as failing.")
  end

  def terminate_child(pid)
    Evilution::ProcessCleanup.safe_kill("TERM", pid)
    _, status = Process.waitpid2(pid, Process::WNOHANG)
    return if status

    sleep(GRACE_PERIOD)
    _, status = Process.waitpid2(pid, Process::WNOHANG)
    return if status

    Evilution::ProcessCleanup.safe_kill("KILL", pid)
    Evilution::ProcessCleanup.safe_wait(pid)
  end

  private

  # Runs in the child. A runner that raises -- a spec helper that cannot load,
  # a framework that is not there -- is a failure with a reason, not a child
  # that dies without a word.
  def child_report(runner, spec_file)
    Report.from(runner.call(spec_file))
  rescue StandardError, ScriptError => e
    Report.build(passed: false, error: "#{e.class}: #{e.message}")
  end

  def timed_out(pid, spec_file)
    terminate_child(pid)
    warn_timeout(spec_file)
    SpecFailure.new(spec_file: spec_file, error: "timed out after #{@timeout}s")
  end

  def unreported_error(status)
    cause = status.signaled? ? "signal #{status.termsig}" : "exit status #{status.exitstatus}"
    "baseline process ended without reporting (#{cause})"
  end

  def warned(failure)
    detail = FailureFormatter.new.call(failure).map { |line| "  #{line}" }
    Evilution::Diagnostic.warn(
      ["[evilution] Baseline failed for #{failure.spec_file}; " \
       "a mutation that fails only its already-failing examples will be reported neutral.", *detail].join("\n")
    )
    failure
  end

  def baseline_spec_files(subjects)
    return Array(@test_files).uniq if @test_files && !@test_files.empty?

    resolve_unique_spec_files(subjects)
  end

  def resolve_unique_spec_files(subjects)
    warned = Set.new
    subjects.flat_map do |s|
      specs = specs_for(s.file_path)
      next specs unless specs.empty?

      warn_no_matching_test(s.file_path) if warned.add?(s.file_path)
      @fallback_to_full_suite ? [@fallback_dir] : []
    end.uniq
  end

  def specs_for(file_path)
    Array(@spec_selector ? @spec_selector.call(file_path) : @spec_resolver.call(file_path))
  end

  def warn_no_matching_test(file_path)
    action = @fallback_to_full_suite ? "running full suite" : "marking its mutations unresolved"
    Evilution::Diagnostic.warn("[evilution] No matching test found for #{file_path}, #{action}. #{no_match_hint(file_path)}")
  end

  def no_match_hint(file_path)
    suggestion = @spec_resolver.suggest(file_path)
    hint = if suggestion
             "Pass --spec #{suggestion} (best guess) or the correct test file"
           else
             "Use --spec to specify the test file"
           end
    @fallback_to_full_suite ? "#{hint}." : "#{hint}, or --fallback-full-suite to run the whole suite."
  end
end

require_relative "baseline/report"
require_relative "baseline/spec_failure"
require_relative "baseline/failure_formatter"
