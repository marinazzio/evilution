# frozen_string_literal: true

require_relative "work_queue"

class Evilution::Parallel::Pool
  def initialize(size:, hooks: nil)
    @queue = Evilution::Parallel::WorkQueue.new(size: size, hooks: hooks)
  end

  def map(items, &)
    @queue.map(items, &)
  end
end
