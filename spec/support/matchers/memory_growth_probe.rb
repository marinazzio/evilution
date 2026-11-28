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
#
# A round does not count the spare room the GC heap gains in it. When a
# collection leaves the heap short of free slots, Ruby lets the heap grow by a
# share of its size before it collects again, so the garbage of the next
# passes lands on new pages and the process grows by that share without
# keeping anything. How big the share is depends on how full the heap happened
# to be, so the same block reads differently from one run to the next. Spare
# room the heap gives back is not credited to the round, since freed pages
# need not leave the process.
#
# Objects the block keeps are counted even when the process does not grow by
# them, because they took room the heap already had spare: a round reports
# whichever is larger, the growth of the process or of the live objects in the
# GC heap.
class MemoryGrowthProbe
  MAX_WARMUP_ROUNDS = 10

  DEFAULT_READER = -> { Evilution::Memory.rss_kb }
  DEFAULT_HEAP_READER = lambda do
    pages_bytes = GC.stat(:heap_allocated_pages) * GC::INTERNAL_CONSTANTS.fetch(:HEAP_PAGE_SIZE)
    live_bytes = GC.stat_heap.each_value.sum do |heap|
      (heap[:total_allocated_objects] - heap[:total_freed_objects]) * heap[:slot_size]
    end
    { live_kb: live_bytes / 1024, spare_kb: (pages_bytes - live_bytes) / 1024 }
  end
  DEFAULT_COLLECTOR = lambda do
    GC.start
    GC.compact if GC.respond_to?(:compact)
  end

  def initialize(iterations:, settled_below_kb:, reader: DEFAULT_READER,
                 heap_reader: DEFAULT_HEAP_READER, collector: DEFAULT_COLLECTOR)
    @iterations = iterations
    @settled_below_kb = settled_below_kb
    @reader = reader
    @heap_reader = heap_reader
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
    after = reading

    spare_gained_kb = [after[:spare_kb] - before[:spare_kb], 0].max
    [after[:rss_kb] - before[:rss_kb] - spare_gained_kb, after[:live_kb] - before[:live_kb]].max
  end

  def reading
    @collector.call
    { rss_kb: @reader.call, **@heap_reader.call }
  end
end
