# frozen_string_literal: true

require_relative "../work_queue"
require_relative "collection_state"

class Evilution::Parallel::WorkQueue::Dispatcher
  attr_reader :first_error

  def initialize(workers:, items:, prefetch:, item_timeout:, worker_max_items:, recycle_factory:)
    @workers = workers
    @items = items
    @prefetch = prefetch
    @item_timeout = item_timeout
    @worker_max_items = worker_max_items
    @recycle_factory = recycle_factory
    @state = Evilution::Parallel::WorkQueue.send(:const_get, :CollectionState).new(items.length)
    @retired = []
  end

  def run
    seed
    collect
    @first_error = @state.first_error
    [@state.results, @retired]
  end

  private

  def seed
    @prefetch.times do
      @workers.each do |w|
        break unless more_to_send?

        send_item(w)
      end
    end
  end

  def collect
    io_to_worker = @workers.to_h { |w| [w.res_io, w] }
    result_ios = io_to_worker.keys

    while @state.in_flight.positive?
      readable, = IO.select(result_ios, nil, nil, @item_timeout)

      if readable.nil?
        terminate_stuck
        @state.first_error ||= Evilution::Error.new("worker timed out after #{@item_timeout}s")
        break
      end

      readable.each do |io|
        alive = handle(io_to_worker[io], io_to_worker, result_ios)
        result_ios.delete(io) unless alive
      end
    end
  end

  def handle(worker, io_to_worker, result_ios)
    message = worker.read_result
    return handle_dead(worker) if message.nil?

    record(message, worker)
    return false if recycle_and_dispatch(worker, io_to_worker, result_ios)
    return true if draining_for_recycle?(worker)

    send_item(worker) if more_to_send? && @state.first_error.nil?
    true
  end

  def record(message, worker)
    index, status, value = message
    @state.first_error = value if status == :error && @state.first_error.nil?
    @state.results[index] = value if status == :ok
    @state.in_flight -= 1
    worker.pending -= 1
    worker.items_completed += 1
  end

  def handle_dead(worker)
    @state.first_error ||= Evilution::Error.new("worker process exited unexpectedly")
    @state.in_flight -= worker.pending
    worker.pending = 0
    false
  end

  def draining_for_recycle?(worker)
    @worker_max_items && worker.items_completed >= @worker_max_items && worker.pending.positive?
  end

  def should_recycle?(worker)
    return false unless @worker_max_items
    return false if worker.items_completed < @worker_max_items
    return false unless worker.pending.zero?
    return false unless more_to_send?

    @state.first_error.nil?
  end

  def recycle_and_dispatch(worker, io_to_worker, result_ios)
    return false unless should_recycle?(worker)

    new_worker = recycle(worker, io_to_worker, result_ios)
    send_item(new_worker) if more_to_send?
    true
  end

  def recycle(old_worker, io_to_worker, result_ios)
    io_to_worker.delete(old_worker.res_io)
    result_ios.delete(old_worker.res_io)
    @retired << old_worker.retire

    new_worker = @recycle_factory.call(old_worker)
    @workers[@workers.index(old_worker)] = new_worker
    io_to_worker[new_worker.res_io] = new_worker
    result_ios << new_worker.res_io
    new_worker
  end

  def send_item(worker)
    worker.send_item(@state.next_index, @items[@state.next_index])
    @state.next_index += 1
    @state.in_flight += 1
  end

  def more_to_send?
    @state.next_index < @items.length
  end

  def terminate_stuck
    @workers.each(&:kill)
  end
end
