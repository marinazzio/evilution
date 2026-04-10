# frozen_string_literal: true

require_relative "../result"

class Evilution::Result::MutationResult
  STATUSES = %i[killed survived timeout error neutral equivalent].freeze

  attr_reader :mutation, :status, :duration, :killing_test, :test_command,
              :child_rss_kb, :memory_delta_kb, :parent_rss_kb,
              :error_message, :error_class, :error_backtrace

  # rubocop:disable Metrics/ParameterLists
  def initialize(mutation:, status:, duration: 0.0, killing_test: nil,
                 test_command: nil, child_rss_kb: nil, memory_delta_kb: nil,
                 parent_rss_kb: nil, error_message: nil, error_class: nil,
                 error_backtrace: nil)
    # rubocop:enable Metrics/ParameterLists
    raise ArgumentError, "invalid status: #{status}" unless STATUSES.include?(status)

    @mutation = mutation
    @status = status
    @duration = duration
    @killing_test = killing_test
    @test_command = test_command
    @child_rss_kb = child_rss_kb
    @memory_delta_kb = memory_delta_kb
    @parent_rss_kb = parent_rss_kb
    @error_message = error_message
    @error_class = error_class
    @error_backtrace = error_backtrace
    freeze
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
end
