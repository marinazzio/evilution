# frozen_string_literal: true

# Stands in for Parallel::Pool: runs the block in this process, finishing the
# items in `order` (input order by default) and streaming each result to
# on_result the way the work queue does, including honouring :stop.
class StreamingPool
  attr_reader :map_calls, :worker_stats, :stopped

  # For a stubbed Pool#map: streams `values` to on_result in input order, as
  # the work queue would, honouring :stop, and returns them.
  def self.replay(values, on_result)
    values.each_with_index do |value, index|
      break if on_result && on_result.call(index, value) == :stop
    end
    values
  end

  def initialize(order: nil, results: nil, waited: nil, worker_stats: [])
    @order = order
    @results = results
    @waited = waited
    @worker_stats = worker_stats
    @map_calls = 0
    @stopped = false
  end

  def map(items, on_result: nil, on_arrival: nil, &block)
    @map_calls += 1
    out = Array.new(items.length)
    (@order || (0...items.length).to_a).each do |i|
      out[i] = @results ? @results[i] : block.call(items[i], @waited)
      on_arrival.call(i, out[i]) if on_arrival
      next unless on_result && on_result.call(i, out[i]) == :stop

      @stopped = true
      break
    end
    out
  end
end
