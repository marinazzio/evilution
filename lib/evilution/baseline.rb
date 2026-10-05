# frozen_string_literal: true

require_relative "spec_resolver"
require_relative "process_cleanup"
require_relative "diagnostic"

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
    read_result(read_io, pid, spec_file)
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

  def read_result(read_io, pid, spec_file)
    if read_io.wait_readable(@timeout)
      data = read_io.read
      Process.wait(pid)
      return false if data.empty?

      result = Marshal.load(data)
      result[:passed]
    else
      terminate_child(pid)
      warn_timeout(spec_file)
      false
    end
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
