# frozen_string_literal: true

require_relative "spec_resolver"
require_relative "process_cleanup"

class Evilution::Baseline
  Result = Struct.new(:failed_spec_files, :duration) do
    def initialize(**)
      super
      freeze
    end

    def failed?
      !failed_spec_files.empty?
    end
  end

  def initialize(spec_resolver: Evilution::SpecResolver.new, timeout: 30, runner: nil,
                 fallback_dir: "spec", test_files: nil)
    @spec_resolver = spec_resolver
    @timeout = timeout
    @runner = runner
    @fallback_dir = fallback_dir
    @test_files = test_files
  end

  def call(subjects)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    spec_files = baseline_spec_files(subjects)
    failed = Set.new

    spec_files.each do |spec_file|
      failed.add(spec_file) unless run_spec_file(spec_file)
    end

    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    Result.new(failed_spec_files: failed, duration: duration)
  end

  def run_spec_file(spec_file)
    raise Evilution::Error, "no baseline runner configured" unless @runner

    read_io, write_io = IO.pipe
    pid = fork_spec_runner(spec_file, read_io, write_io)
    write_io.close
    read_result(read_io, pid)
  rescue Evilution::Error
    raise
  rescue StandardError
    false
  ensure
    read_io&.close
    write_io&.close
  end

  def fork_spec_runner(spec_file, read_io, write_io)
    runner = @runner
    Process.fork do
      read_io.close
      $stdout.reopen(File::NULL, "w")
      $stderr.reopen(File::NULL, "w")

      passed = runner.call(spec_file)
      Marshal.dump({ passed: passed }, write_io)
      write_io.close
      exit!(passed ? 0 : 1)
    end
  end

  GRACE_PERIOD = 0.5

  def read_result(read_io, pid)
    if read_io.wait_readable(@timeout)
      data = read_io.read
      Process.wait(pid)
      return false if data.empty?

      result = Marshal.load(data)
      result[:passed]
    else
      terminate_child(pid)
      false
    end
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

  # When --spec was provided, run those files only. Auto-discovery is skipped
  # entirely — the user has declared what covers their subjects and any
  # mismatch between auto-discovery and their declaration is what produced
  # the misleading "No matching test found" warning users have reported even
  # while passing --spec.
  def baseline_spec_files(subjects)
    return Array(@test_files).uniq if @test_files && !@test_files.empty?

    resolve_unique_spec_files(subjects)
  end

  def resolve_unique_spec_files(subjects)
    warned = Set.new
    subjects.map do |s|
      resolved = @spec_resolver.call(s.file_path)
      warn_no_matching_test(s.file_path) if resolved.nil? && warned.add?(s.file_path)
      resolved || @fallback_dir
    end.uniq
  end

  def warn_no_matching_test(file_path)
    suggestion = @spec_resolver.suggest(file_path)
    hint = if suggestion
             "Pass --spec #{suggestion} (best guess) or the correct test file."
           else
             "Use --spec to specify the test file."
           end
    warn "[evilution] No matching test found for #{file_path}, running full suite. #{hint}"
  end
end
