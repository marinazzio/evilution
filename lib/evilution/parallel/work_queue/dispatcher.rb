# frozen_string_literal: true

require_relative "../work_queue"
require_relative "collection_state"

class Evilution::Parallel::WorkQueue::Dispatcher
  RunResult = Data.define(:results, :retired)

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
    @deadlines = DeadlineTracker.new(item_timeout: item_timeout, workers: @workers)
  end

  def run
    seed
    collect
    @first_error = @state.first_error
    RunResult.new(results: @state.results, retired: @retired)
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

  # Each worker carries its own deadline (set when it goes busy, refreshed on
  # every result). The select blocks only until the nearest worker deadline,
  # so a single stuck worker is reaped in isolation -- its in-flight item gets
  # the WorkQueue::TIMED_OUT sentinel and the worker is recycled -- instead of
  # the old pool-wide watchdog that SIGKILLed every worker and aborted the run.
  def collect
    io_to_worker = @workers.to_h { |w| [w.res_io, w] }
    result_ios = io_to_worker.keys

    while @state.in_flight.positive?
      readable, = IO.select(result_ios, nil, nil, @deadlines.select_timeout)
      reap_timed_out(io_to_worker, result_ios)
      next if readable.nil?

      readable.each do |io|
        process_readable(io, io_to_worker, result_ios) if result_ios.include?(io)
      end
    end
  end

  def reap_timed_out(io_to_worker, result_ios)
    @deadlines.overdue.each { |worker| time_out_worker(worker, io_to_worker, result_ios) }
  end

  def time_out_worker(worker, io_to_worker, result_ios)
    worker.kill
    mark_unfinished(worker, Evilution::Parallel::WorkQueue::TIMED_OUT)
    retire_or_replace(worker, io_to_worker, result_ios)
  end

  def process_readable(io, io_to_worker, result_ios)
    alive = handle(io_to_worker[io], io_to_worker, result_ios)
    result_ios.delete(io) unless alive
  end

  def handle(worker, io_to_worker, result_ios)
    message = worker.read_result
    return handle_dead(worker, io_to_worker, result_ios) if message.nil?

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
    worker.in_flight_indices.delete(index)
    @deadlines.refresh(worker)
  end

  # A worker that exited without replying loses only its in-flight item(s)
  # (marked :died) and is recycled; the run continues rather than aborting.
  def handle_dead(worker, io_to_worker, result_ios)
    mark_unfinished(worker, Evilution::Parallel::WorkQueue::DIED)
    retire_or_replace(worker, io_to_worker, result_ios)
    false
  end

  def mark_unfinished(worker, sentinel)
    worker.in_flight_indices.each { |index| @state.results[index] = sentinel }
    @state.in_flight -= worker.pending
    worker.pending = 0
    worker.in_flight_indices.clear
    worker.deadline = nil
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
    index = @workers.index(old_worker)
    detach(old_worker, io_to_worker, result_ios)
    new_worker = @recycle_factory.call(old_worker)
    @workers[index] = new_worker
    attach(new_worker, io_to_worker, result_ios)
    new_worker
  end

  # Shared failure-path recovery: retire the worker, and as long as work
  # remains spin up a replacement to keep the pool full and hand it the next
  # item. When the queue is already drained, just drop the worker.
  def retire_or_replace(worker, io_to_worker, result_ios)
    index = @workers.index(worker)
    detach(worker, io_to_worker, result_ios)

    if more_to_send? && @state.first_error.nil?
      new_worker = @recycle_factory.call(worker)
      @workers[index] = new_worker
      attach(new_worker, io_to_worker, result_ios)
      send_item(new_worker)
    else
      @workers.delete_at(index)
    end
  end

  def detach(worker, io_to_worker, result_ios)
    io_to_worker.delete(worker.res_io)
    result_ios.delete(worker.res_io)
    @retired << worker.retire
  end

  def attach(worker, io_to_worker, result_ios)
    io_to_worker[worker.res_io] = worker
    result_ios << worker.res_io
  end

  def send_item(worker)
    worker.send_item(@state.next_index, @items[@state.next_index])
    @state.next_index += 1
    @state.in_flight += 1
    @deadlines.start(worker)
  end

  def more_to_send?
    @state.next_index < @items.length
  end
end

require_relative "dispatcher/deadline_tracker"
