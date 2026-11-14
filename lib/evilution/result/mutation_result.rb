# frozen_string_literal: true

require_relative "../result"
require_relative "error_info"
require_relative "memory_stats"
require_relative "mutation_timings"

class Evilution::Result::MutationResult
  STATUSES = %i[killed survived timeout error neutral equivalent unresolved unparseable uncovered].freeze

  attr_reader :mutation, :status, :duration, :killing_test, :test_command, :memory, :error, :neutral_reason,
              :time_limit

  # known_failures_only: the tests failed, but every example that did was
  # already failing before any mutation ran, so the failure says nothing
  # about this one.
  #
  # time_limit: the seconds the test run was allowed, recorded on a run that
  # used them up so a reader can tell a short adaptive limit from a long one.
  def initialize(mutation:, status:, duration: 0.0, killing_test: nil,
                 test_command: nil, memory: nil, error: nil, neutral_reason: nil, known_failures_only: false,
                 timings: nil, time_limit: nil)
    raise ArgumentError, "invalid status: #{status}" unless STATUSES.include?(status)

    @mutation = mutation
    @status = status
    @duration = duration
    @killing_test = killing_test
    @test_command = test_command
    @memory = memory
    @error = error
    @neutral_reason = neutral_reason
    @known_failures_only = known_failures_only == true
    @timings = timings
    @time_limit = time_limit
    freeze
  end

  def with_time_limit(seconds)
    self.class.new(
      mutation: @mutation, status: @status, duration: @duration, killing_test: @killing_test,
      test_command: @test_command, memory: @memory, error: @error, neutral_reason: @neutral_reason,
      known_failures_only: @known_failures_only, timings: @timings, time_limit: seconds
    )
  end

  # Where the duration went (Evilution::Result::MutationTimings), when the
  # test process measured it.
  def timings
    @timings.is_a?(Evilution::Result::MutationTimings) ? @timings : nil
  end

  # Positive type checks, not nil checks. EV-s5br / GH #1174: the
  # nil_replacement mutator can swap a nil default into `false` (or some other
  # non-typed value), and `nil?` then returns false, sending a missing method
  # to the wrong receiver and crashing the parent worker. Asking the field
  # explicitly whether it is the expected struct keeps the parent process
  # alive and lets the mutation count as a measured (errored) result.
  def child_rss_kb
    @memory.is_a?(Evilution::Result::MemoryStats) ? @memory.child_rss_kb : nil
  end

  def memory_delta_kb
    @memory.is_a?(Evilution::Result::MemoryStats) ? @memory.memory_delta_kb : nil
  end

  def parent_rss_kb
    @memory.is_a?(Evilution::Result::MemoryStats) ? @memory.parent_rss_kb : nil
  end

  def error_message
    @error.is_a?(Evilution::Result::ErrorInfo) ? @error.message : nil
  end

  def error_class
    @error.is_a?(Evilution::Result::ErrorInfo) ? @error.klass : nil
  end

  def error_backtrace
    @error.is_a?(Evilution::Result::ErrorInfo) ? @error.backtrace : nil
  end

  def known_failures_only?
    @known_failures_only
  end

  def killed?
    status == :killed
  end

  def survived?
    status == :survived
  end

  def timeout?
    status == :timeout
  end

  def error?
    status == :error
  end

  def neutral?
    status == :neutral
  end

  def equivalent?
    status == :equivalent
  end

  def unresolved?
    status == :unresolved
  end

  def unparseable?
    status == :unparseable
  end

  # No test executes a line the mutation sits on, so it was never run: it
  # could only have survived. Scored as a survivor, but kept apart from them.
  def uncovered?
    status == :uncovered
  end
end
