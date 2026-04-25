# frozen_string_literal: true

require_relative "../parallel"

class Evilution::Parallel::WorkQueue
  SHUTDOWN = :__shutdown__

  STATS = :__stats__

  TIMING_GRACE_PERIOD = 5

  def initialize(size:, hooks: nil, prefetch: 1, item_timeout: nil, worker_max_items: nil)
    Validators::PositiveInt.call!(:size, size)
    Validators::PositiveInt.call!(:prefetch, prefetch)
    Validators::OptionalPositiveNumber.call!(:item_timeout, item_timeout)
    Validators::OptionalPositiveInt.call!(:worker_max_items, worker_max_items)

    @size = size
    @hooks = hooks
    @prefetch = prefetch
    @item_timeout = item_timeout
    @worker_max_items = worker_max_items
    @worker_stats = []
  end

  def map(items, &block)
    return [] if items.empty?

    @retired_workers = []
    worker_count = [@size, items.length].min
    workers = (0...worker_count).map { |slot| spawn_one(slot, &block) }

    begin
      distribute_and_collect(items, workers, &block)
    ensure
      workers.each(&:shutdown)
      collect_final_timings(workers)
      workers.each(&:close_pipes)
      workers.each(&:reap)
      @worker_stats = @retired_workers + workers.map(&:to_stat)
      @retired_workers = nil
    end
  end

  def worker_stats
    @worker_stats.map { |stat| stat.dup.freeze }
  end

  private

  def spawn_one(worker_index, &)
    Worker.spawn(worker_index: worker_index, hooks: @hooks, &)
  end

  def distribute_and_collect(items, workers, &)
    state = CollectionState.new(items.length)
    seed_workers(items, workers, state)
    collect_results(items, workers, state, &)
    raise state.first_error if state.first_error

    state.results
  end

  def seed_workers(items, workers, state)
    @prefetch.times do
      workers.each do |worker|
        break unless state.next_index < items.length

        send_item(worker, items, state)
      end
    end
  end

  def collect_results(items, workers, state, &block)
    io_to_worker = workers.to_h { |w| [w.res_io, w] }
    result_ios = io_to_worker.keys

    while state.in_flight.positive?
      readable, = IO.select(result_ios, nil, nil, @item_timeout)

      if readable.nil?
        workers.each(&:kill)
        state.first_error = Evilution::Error.new("worker timed out after #{@item_timeout}s") if state.first_error.nil?
        break
      end

      readable.each do |io|
        alive = handle_result(io, io_to_worker[io], items, state, workers, io_to_worker, result_ios, &block)
        result_ios.delete(io) unless alive
      end
    end
  end

  def handle_result(io, worker, items, state, workers, io_to_worker, result_ios, &)
    message = Evilution::Parallel::WorkQueue::Channel.read(io)
    return handle_dead_worker(worker, state) if message.nil?

    record_result(message, worker, state)
    return false if recycle_and_dispatch(worker, items, state, workers, io_to_worker, result_ios, &)
    return true if draining_for_recycle?(worker)

    send_item(worker, items, state) if state.next_index < items.length && state.first_error.nil?
    true
  end

  # Once worker hits K, stop dispatching so pending drains to 0; recycle fires
  # on the next result. Prevents prefetch > 1 from refilling pending forever.
  def draining_for_recycle?(worker)
    @worker_max_items && worker.items_completed >= @worker_max_items && worker.pending.positive?
  end

  def handle_dead_worker(worker, state)
    state.first_error = Evilution::Error.new("worker process exited unexpectedly") if state.first_error.nil?
    state.in_flight -= worker.pending
    worker.pending = 0
    false
  end

  def record_result(message, worker, state)
    index, status, value = message
    state.first_error = value if status == :error && state.first_error.nil?
    state.results[index] = value if status == :ok
    state.in_flight -= 1
    worker.pending -= 1
    worker.items_completed += 1
  end

  def recycle_and_dispatch(worker, items, state, workers, io_to_worker, result_ios, &)
    return false unless should_recycle?(worker, state, items)

    io_to_worker.delete(worker.res_io)
    result_ios.delete(worker.res_io)
    @retired_workers << worker.retire

    new_worker = spawn_one(worker.worker_index, &)
    workers[workers.index(worker)] = new_worker
    io_to_worker[new_worker.res_io] = new_worker
    result_ios << new_worker.res_io

    send_item(new_worker, items, state) if state.next_index < items.length && state.first_error.nil?
    true
  end

  def should_recycle?(worker, state, items)
    return false unless @worker_max_items
    return false if worker.items_completed < @worker_max_items
    return false unless worker.pending.zero?
    return false unless state.next_index < items.length
    return false unless state.first_error.nil?

    true
  end

  def send_item(worker, items, state)
    worker.send_item(state.next_index, items[state.next_index])
    state.next_index += 1
    state.in_flight += 1
  end

  def collect_final_timings(workers)
    io_to_worker = workers.reject { |w| w.res_io.closed? }.to_h { |w| [w.res_io, w] }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMING_GRACE_PERIOD

    until io_to_worker.empty?
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      break if remaining <= 0

      readable, = IO.select(io_to_worker.keys, nil, nil, remaining)
      break unless readable

      readable.each { |io| apply_final_timing(io_to_worker.delete(io), io) }
    end
  end

  def apply_final_timing(worker, io)
    message = Evilution::Parallel::WorkQueue::Channel.read(io)
    return if message.nil?

    tag, busy_time, wall_time = message
    return unless tag == STATS

    worker.busy_time = busy_time
    worker.wall_time = wall_time
  end

  CollectionState = Struct.new(:results, :in_flight, :next_index, :first_error) do
    def initialize(item_count)
      super(Array.new(item_count), 0, 0, nil)
    end
  end
  private_constant :CollectionState
end

require_relative "work_queue/worker_stat"
require_relative "work_queue/validators"
require_relative "work_queue/validators/positive_int"
require_relative "work_queue/validators/optional_positive_int"
require_relative "work_queue/validators/optional_positive_number"
require_relative "work_queue/channel"
require_relative "work_queue/channel/frame"
require_relative "work_queue/worker"
require_relative "work_queue/worker/loop"
