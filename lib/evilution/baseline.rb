# frozen_string_literal: true

require_relative "spec_resolver"

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

  def initialize(spec_resolver: Evilution::SpecResolver.new, timeout: 30, runner: nil, fallback_dir: "spec")
    @spec_resolver = spec_resolver
    @timeout = timeout
    @runner = runner
    @fallback_dir = fallback_dir
  end

  def call(subjects)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    spec_files = resolve_unique_spec_files(subjects)
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

      result = Marshal.load(data) # rubocop:disable Security/MarshalLoad
      result[:passed]
    else
      terminate_child(pid)
      false
    end
  end

  def terminate_child(pid)
    Process.kill("TERM", pid) rescue nil # rubocop:disable Style/RescueModifier
    _, status = Process.waitpid2(pid, Process::WNOHANG)
    return if status

    sleep(GRACE_PERIOD)
    _, status = Process.waitpid2(pid, Process::WNOHANG)
    return if status

    Process.kill("KILL", pid) rescue nil # rubocop:disable Style/RescueModifier
    Process.wait(pid) rescue nil # rubocop:disable Style/RescueModifier
  end

  private

  def resolve_unique_spec_files(subjects)
    warned = Set.new
    subjects.map do |s|
      resolved = @spec_resolver.call(s.file_path)
      if resolved.nil? && warned.add?(s.file_path)
        warn "[evilution] No matching test found for #{s.file_path}, running full suite. " \
             "Use --spec to specify the test file."
      end
      resolved || @fallback_dir
    end.uniq
  end
end
