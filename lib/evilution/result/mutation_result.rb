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

  def child_rss_kb
    @memory.nil? ? nil : @memory.child_rss_kb
  end

  def memory_delta_kb
    @memory.nil? ? nil : @memory.memory_delta_kb
  end

  def parent_rss_kb
    @memory.nil? ? nil : @memory.parent_rss_kb
  end

  def error_message
    @error.nil? ? nil : @error.message
  end

  def error_class
    @error.nil? ? nil : @error.klass
  end

  def error_backtrace
    @error.nil? ? nil : @error.backtrace
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
