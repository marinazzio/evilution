# frozen_string_literal: true

require_relative "work_queue"

class Evilution::Parallel::Pool
  def initialize(size:, hooks: nil, item_timeout: nil)
    @queue = Evilution::Parallel::WorkQueue.new(size: size, hooks: hooks, item_timeout: item_timeout)
  end

  def map(items, &)
    @queue.map(items, &)
  end

  def worker_stats
    @queue.worker_stats
  end
end
