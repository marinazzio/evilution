# frozen_string_literal: true

require "evilution/memory"

# Measures how much a block grows the process once it has stopped warming up.
#
# The first passes of anything allocate what later passes reuse: the heap
# grows to its working size, caches fill. Read from a cold start, that is
# indistinguishable from a leak, and how large it is depends on the Ruby and
# on what the process did before. So the block is run in rounds until one
# round grows the process by no more than `settled_below_kb`, and only the
# round after that is reported. A leak never settles: the rounds run out and
# the reading still shows it.
class MemoryGrowthProbe
  MAX_WARMUP_ROUNDS = 10

  DEFAULT_READER = -> { Evilution::Memory.rss_kb }
  DEFAULT_COLLECTOR = lambda do
    GC.start
    GC.compact if GC.respond_to?(:compact)
  end

  def initialize(iterations:, settled_below_kb:, reader: DEFAULT_READER, collector: DEFAULT_COLLECTOR)
    @iterations = iterations
    @settled_below_kb = settled_below_kb
    @reader = reader
    @collector = collector
  end

  # Growth, in KB, over one round of the block after warm-up.
  def call(&block)
    MAX_WARMUP_ROUNDS.times { break if round(block) <= @settled_below_kb }
    round(block)
  end

  private

  def round(block)
    before = reading
    @iterations.times { block.call }
    reading - before
  end

  def reading
    @collector.call
    @reader.call
  end
end
