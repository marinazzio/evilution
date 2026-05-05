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

    workers = (0...[@size, items.length].min).map { |i| spawn_one(i, &block) }
    dispatcher = build_dispatcher(workers, items, &block)

    retired = []
    begin
      results, retired = dispatcher.run
      raise dispatcher.first_error if dispatcher.first_error

      results
    ensure
      cleanup_workers(workers, retired)
    end
  end

  def worker_stats
    @worker_stats.map { |stat| stat.dup.freeze }
  end

  private

  def spawn_one(worker_index, &)
    Worker.spawn(worker_index: worker_index, hooks: @hooks, &)
  end

  def build_dispatcher(workers, items, &block)
    Dispatcher.new(
      workers: workers, items: items, prefetch: @prefetch,
      item_timeout: @item_timeout, worker_max_items: @worker_max_items,
      recycle_factory: ->(old) { spawn_one(old.worker_index, &block) }
    )
  end

  def cleanup_workers(workers, retired)
    workers.each(&:shutdown)
    collect_final_timings(workers)
    workers.each(&:close_pipes)
    workers.each(&:reap)
    @worker_stats = retired + workers.map(&:to_stat)
  end

  def collect_final_timings(workers)
    io_to_worker = workers.reject { |w| w.res_io.closed? }.to_h { |w| [w.res_io, w] }
    deadline = monotonic_now + TIMING_GRACE_PERIOD

    until io_to_worker.empty?
      remaining = deadline - monotonic_now
      break if remaining <= 0
      break unless poll_and_apply(io_to_worker, remaining)
    end
  end

  def poll_and_apply(io_to_worker, remaining)
    readable, = IO.select(io_to_worker.keys, nil, nil, remaining)
    return false unless readable

    readable.each { |io| apply_final_timing(io_to_worker.delete(io), io) }
    true
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def apply_final_timing(worker, io)
    message = Evilution::Parallel::WorkQueue::Channel.read(io)
    return if message.nil?

    tag, busy_time, wall_time = message
    return unless tag == STATS

    worker.busy_time = busy_time
    worker.wall_time = wall_time
  end
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
require_relative "work_queue/collection_state"
require_relative "work_queue/dispatcher"
