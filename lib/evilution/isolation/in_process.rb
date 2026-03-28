# frozen_string_literal: true

require "timeout"
require_relative "../memory"
require_relative "../result/mutation_result"

require_relative "../isolation"

class Evilution::Isolation::InProcess
  def call(mutation:, test_command:, timeout:)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rss_before = Evilution::Memory.rss_kb
    result = execute_with_timeout(mutation, test_command, timeout)
    rss_after = Evilution::Memory.rss_kb
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    delta = compute_memory_delta(rss_before, rss_after, result)

    build_mutation_result(mutation, result, duration, rss_after, delta)
  end

  private

  def execute_with_timeout(mutation, test_command, timeout)
    result = Timeout.timeout(timeout) do
      suppress_output { test_command.call(mutation) }
    end
    { timeout: false }.merge(result)
  rescue Timeout::Error
    { timeout: true }
  rescue StandardError => e
    { timeout: false, passed: false, error: e.message }
  end

  def suppress_output
    saved_stdout = $stdout
    saved_stderr = $stderr
    File.open(File::NULL, "w") do |null_out|
      File.open(File::NULL, "w") do |null_err|
        $stdout = null_out
        $stderr = null_err
        yield
      end
    end
  ensure
    $stdout = saved_stdout
    $stderr = saved_stderr
  end

  def compute_memory_delta(rss_before, rss_after, result)
    return nil if result[:timeout]
    return nil unless rss_before && rss_after

    rss_after - rss_before
  end

  def build_mutation_result(mutation, result, duration, rss_after, memory_delta_kb)
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
      child_rss_kb: rss_after,
      memory_delta_kb: memory_delta_kb
    )
  end
end
