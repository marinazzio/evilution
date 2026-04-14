# frozen_string_literal: true

require "timeout"
require_relative "../memory"
require_relative "../result/mutation_result"

require_relative "../isolation"

class Evilution::Isolation::InProcess
  @null_out = File.open(File::NULL, "w")
  @null_err = File.open(File::NULL, "w")

  class << self
    attr_reader :null_out, :null_err
  end

  def call(mutation:, test_command:, timeout:)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rss_before = Evilution::Memory.rss_kb
    result = execute_with_timeout(mutation, test_command, timeout)
    rss_after = Evilution::Memory.rss_kb
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    delta = compute_memory_delta(rss_before, rss_after, result)

    build_mutation_result(mutation, result, duration, rss_before, rss_after, delta)
  end

  private

  def execute_with_timeout(mutation, test_command, timeout)
    result = Timeout.timeout(timeout) do
      suppress_output { test_command.call(mutation) }
    end
    { timeout: false }.merge(result)
  rescue Timeout::Error
    { timeout: true }
  rescue ScriptError, StandardError => e
    {
      timeout: false,
      passed: false,
      error: e.message,
      error_class: e.class.name,
      error_backtrace: Array(e.backtrace).first(5)
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
    return :killed if result[:test_crashed]
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
      child_rss_kb: rss_after,
      memory_delta_kb: memory_delta_kb,
      parent_rss_kb: rss_before,
      error_message: result[:error],
      error_class: result[:error_class],
      error_backtrace: result[:error_backtrace]
    )
  end
end
