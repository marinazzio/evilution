# frozen_string_literal: true

require_relative "../mutation_executor"
require_relative "../../result/mutation_result"

class Evilution::Runner::MutationExecutor::ResultPacker
  def compact(result)
    run_fields(result).merge(memory_fields(result), error_fields(result))
  end

  def rebuild(mutation, data)
    Evilution::Result::MutationResult.new(
      mutation: mutation,
      status: data[:status],
      duration: data[:duration],
      killing_test: data[:killing_test],
      test_command: data[:test_command],
      memory: rebuild_memory(data),
      error: rebuild_error(data),
      known_failures_only: data[:known_failures_only],
      timings: rebuild_timings(data),
      time_limit: data[:time_limit],
      examples_run: data[:examples_run],
      implied_by: data[:implied_by]
    )
  end

  private

  def run_fields(result)
    {
      status: result.status,
      duration: result.duration,
      killing_test: result.killing_test,
      test_command: result.test_command,
      known_failures_only: result.known_failures_only?,
      timings: result.timings ? result.timings.to_h : nil,
      time_limit: result.time_limit,
      examples_run: result.examples_run,
      implied_by: result.implied_by
    }
  end

  def memory_fields(result)
    { child_rss_kb: result.child_rss_kb, memory_delta_kb: result.memory_delta_kb, parent_rss_kb: result.parent_rss_kb }
  end

  def error_fields(result)
    { error_message: result.error_message, error_class: result.error_class, error_backtrace: result.error_backtrace }
  end

  def rebuild_memory(data)
    Evilution::Result::MemoryStats.from_fields(
      child_rss_kb: data[:child_rss_kb], memory_delta_kb: data[:memory_delta_kb], parent_rss_kb: data[:parent_rss_kb]
    )
  end

  def rebuild_error(data)
    Evilution::Result::ErrorInfo.from_fields(
      message: data[:error_message], klass: data[:error_class], backtrace: data[:error_backtrace]
    )
  end

  # queue_wait is measured in the worker around the isolated run, so it
  # arrives beside the result's own timings rather than inside them.
  def rebuild_timings(data)
    timings = Evilution::Result::MutationTimings.from_h(data[:timings])
    wait = data[:queue_wait]
    return timings unless wait.is_a?(Numeric)

    timings ? timings.with_queue_wait(wait) : Evilution::Result::MutationTimings.new(queue_wait: wait)
  end
end
