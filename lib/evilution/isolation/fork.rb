# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../memory"

require_relative "../isolation"

class Evilution::Isolation::Fork
  GRACE_PERIOD = 2

  def initialize(hooks: nil)
    @hooks = hooks
  end

  def call(mutation:, test_command:, timeout:)
    sandbox_dir = Dir.mktmpdir("evilution-run")
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    read_io, write_io = IO.pipe

    pid = ::Process.fork do
      ENV["TMPDIR"] = sandbox_dir
      read_io.close
      suppress_child_output
      @hooks.fire(:worker_process_start, mutation: mutation) if @hooks
      result = execute_in_child(mutation, test_command)
      Marshal.dump(result, write_io)
      write_io.close
      exit!(result[:passed] ? 0 : 1)
    end

    write_io.close
    result = wait_for_result(pid, read_io, timeout)
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

    build_mutation_result(mutation, result, duration)
  ensure
    read_io&.close
    write_io&.close
    restore_original_source(mutation)
    FileUtils.rm_rf(sandbox_dir) if sandbox_dir
  end

  private

  def restore_original_source(mutation)
    return if File.read(mutation.file_path) == mutation.original_source

    File.write(mutation.file_path, mutation.original_source)
  rescue StandardError => e
    warn("Warning: failed to restore #{mutation.file_path}: #{e.message}")
  end

  def suppress_child_output
    $stdout.reopen(File::NULL, "w")
    $stderr.reopen(File::NULL, "w")
  end

  def execute_in_child(mutation, test_command)
    result = test_command.call(mutation)
    { child_rss_kb: Evilution::Memory.rss_kb }.merge(result)
  rescue StandardError => e
    { passed: false, error: e.message }
  end

  def wait_for_result(pid, read_io, timeout)
    if read_io.wait_readable(timeout)
      data = read_io.read
      ::Process.wait(pid)

      if data.empty?
        { timeout: false, passed: false, error: "empty result from child" }
      else
        { timeout: false }.merge(Marshal.load(data)) # rubocop:disable Security/MarshalLoad
      end
    else
      terminate_child(pid)
      { timeout: true }
    end
  end

  def terminate_child(pid)
    ::Process.kill("TERM", pid) rescue nil # rubocop:disable Style/RescueModifier
    _, status = ::Process.waitpid2(pid, ::Process::WNOHANG)
    return if status

    sleep(GRACE_PERIOD)
    _, status = ::Process.waitpid2(pid, ::Process::WNOHANG)
    return if status

    ::Process.kill("KILL", pid) rescue nil # rubocop:disable Style/RescueModifier
    ::Process.wait(pid) rescue nil # rubocop:disable Style/RescueModifier
  end

  def build_mutation_result(mutation, result, duration)
    status = if result[:timeout]
               :timeout
             elsif result[:error]
               :error
             elsif result[:passed]
               :survived
             else
               :killed
             end

    Evilution::Result::MutationResult.new(
      mutation: mutation,
      status: status,
      duration: duration,
      test_command: result[:test_command],
      child_rss_kb: result[:child_rss_kb]
    )
  end
end
