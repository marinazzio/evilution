# frozen_string_literal: true

require_relative "../dispatcher"

# Hands the Dispatcher's caller each finished item, (index, value), in the
# order the items finish, and keeps the caller's answer: :stop means no further
# item is to be sent. The Dispatcher pushes as results come in and flushes
# once the round's workers have their next item, so the caller's handling never
# holds a worker idle.
class Evilution::Parallel::WorkQueue::Dispatcher::ResultStream
  # Stands in for a caller that takes the results at the end of the run only.
  IGNORE = ->(_index, _value) {}
  private_constant :IGNORE

  def initialize(on_result)
    @on_result = on_result || IGNORE
    @finished = []
    @stopped = false
  end

  def push(index, value)
    @finished << [index, value]
  end

  def flush
    until @finished.empty?
      index, value = @finished.shift
      @stopped = true if @on_result.call(index, value) == :stop
    end
  end

  def stopped?
    @stopped
  end
end
