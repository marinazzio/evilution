# frozen_string_literal: true

require_relative "../dispatcher"
require_relative "../channel"

# Reads what a worker sent and says what it is: a result of an item the worker
# holds, the end of its stream (nil), or something that cannot be trusted.
#
# The result pipe is inherited by the processes a worker forks, so a frame on
# it is not always the worker's. One that does not decode is UNREADABLE, and
# so is one that decodes to something other than a result: what a stray
# process writes may happen to be a marshal dump, and taken at its word it
# would move the Dispatcher's counters or be raised as the error of the run.
# After either, the stream is out of step, and the Dispatcher gives the worker
# up.
#
# Keeping the wire-level judgement here leaves the Dispatcher with what to do
# about each answer.
module Evilution::Parallel::WorkQueue::Dispatcher::Reply
  UNREADABLE = Object.new.freeze

  module_function

  def from(worker)
    message = worker.read_result
    return nil if message.nil?

    result_of?(worker, message) ? message : UNREADABLE
  rescue Evilution::Parallel::WorkQueue::Channel::BadFrame
    UNREADABLE
  end

  def result_of?(worker, message)
    return false unless message.is_a?(Array) && message.length == 3

    index, status, value = message
    return false unless worker.in_flight_indices.include?(index)

    status == :ok || (status == :error && value.is_a?(Exception))
  end
end
