# frozen_string_literal: true

require_relative "../parallel"
require_relative "work_queue"

class Evilution::Parallel::Pool
  # `worker_max_items` is how many items a worker runs before it is replaced by
  # a fresh one; nil keeps every worker for the whole run.
  def initialize(size:, hooks: nil, item_timeout: nil, worker_max_items: nil)
    @queue = Evilution::Parallel::WorkQueue.new(
      size: size, hooks: hooks, item_timeout: item_timeout, worker_max_items: worker_max_items
    )
  end

  def map(items, on_result: nil, on_arrival: nil, &)
    @queue.map(items, on_result: on_result, on_arrival: on_arrival, &)
  end

  def worker_stats
    @queue.worker_stats
  end
end
