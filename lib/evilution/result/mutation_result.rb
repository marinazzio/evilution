# frozen_string_literal: true

require_relative "../result"
require_relative "error_info"
require_relative "memory_stats"

class Evilution::Result::MutationResult
  STATUSES = %i[killed survived timeout error neutral equivalent unresolved unparseable].freeze

  attr_reader :mutation, :status, :duration, :killing_test, :test_command, :memory, :error

  def initialize(mutation:, status:, duration: 0.0, killing_test: nil,
                 test_command: nil, memory: nil, error: nil)
    raise ArgumentError, "invalid status: #{status}" unless STATUSES.include?(status)

    @mutation = mutation
    @status = status
    @duration = duration
    @killing_test = killing_test
    @test_command = test_command
    @memory = memory
    @error = error
    freeze
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
end
