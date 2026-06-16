# frozen_string_literal: true

require_relative "../dispatcher"

# Owns the per-worker item-timeout deadline clock for the Dispatcher: arming a
# worker's deadline when it goes busy, re-arming it on each result, surfacing the
# workers whose deadline has passed, and computing how long IO.select may block.
# Each worker carries its own deadline so a single stuck worker is reaped in
# isolation rather than aborting the whole pool (EV-gl1e). Pulling this cohesive
# timeout concern out of the Dispatcher keeps the dispatcher focused on the
# collect/recycle orchestration (EV-9mij).
#
# `workers` is the Dispatcher's live array (mutated in place as workers recycle),
# so the tracker always reads the current pool. `clock` is injectable for tests.
class Evilution::Parallel::WorkQueue::Dispatcher::DeadlineTracker
  def initialize(item_timeout:, workers:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @item_timeout = item_timeout
    @workers = workers
    @clock = clock
  end

  def enabled?
    !@item_timeout.nil?
  end

  # Seconds IO.select may block: until the nearest worker deadline (never
  # negative), or the raw timeout when no worker is currently on the clock.
  def select_timeout
    return @item_timeout unless enabled?

    deadlines = @workers.filter_map(&:deadline)
    return @item_timeout if deadlines.empty?

    [deadlines.min - now, 0].max
  end

  # Workers whose deadline has passed while still holding in-flight work.
  def overdue
    return [] unless enabled?

    moment = now
    @workers.select { |worker| worker.deadline && worker.deadline <= moment && worker.pending.positive? }
  end

  # Arm a worker's clock when it first goes busy; idempotent for the in-flight
  # item so a refresh does not extend an already-running deadline.
  def start(worker)
    return unless enabled?

    worker.deadline ||= now + @item_timeout
  end

  # After a result: re-arm while work remains, otherwise stop the clock.
  def refresh(worker)
    worker.deadline = (now + @item_timeout if enabled? && worker.pending.positive?)
  end

  private

  def now
    @clock.call
  end
end
