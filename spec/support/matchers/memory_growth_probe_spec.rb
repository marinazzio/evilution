# frozen_string_literal: true

require_relative "memory_growth_probe"

RSpec.describe MemoryGrowthProbe do
  # A process whose memory is whatever the block has made of it: each pass
  # adds the next entry of `costs` (then nothing), so warm-up is a list that
  # tapers off and a leak is one that does not. Each pass also moves the pages
  # of the GC heap and the live objects on them by the next entries of `pages`
  # and `live`; the heap starts with some of both, and its spare room is the
  # pages the live objects do not take. What that costs the process is up to
  # `costs`.
  def probe_over(costs, iterations: 2, settled_below_kb: 10, live: [], pages: [])
    process = { rss: 1000, pages_kb: 50_000, live_kb: 40_000 }
    remaining = { rss: costs, pages_kb: pages, live_kb: live }.transform_values(&:dup)
    passes = 0
    block = lambda do
      passes += 1
      remaining.each { |key, entries| process[key] += entries.shift || 0 }
    end
    probe = described_class.new(iterations: iterations, settled_below_kb: settled_below_kb,
                                reader: -> { process[:rss] },
                                heap_reader: -> { process.slice(:pages_kb, :live_kb) }, collector: -> {})
    [probe.call(&block), passes]
  end

  it "reports no growth for a block that costs nothing" do
    growth, = probe_over([])

    expect(growth).to eq(0)
  end

  it "does not count growth that tapers off before the reading" do
    growth, = probe_over([500, 500, 200, 100, 4, 3, 1, 1])

    expect(growth).to eq(2)
  end

  it "reads one round after the first that settled" do
    _, passes = probe_over([500, 500, 3, 3])

    expect(passes).to eq(6)
  end

  it "reads straight after a first round that is already settled" do
    _, passes = probe_over([])

    expect(passes).to eq(4)
  end

  it "counts a round that grows by exactly the settling threshold as settled" do
    _, passes = probe_over([5, 5, 0, 0], settled_below_kb: 10)

    expect(passes).to eq(4)
  end

  it "still reports a leak, which never settles" do
    growth, passes = probe_over(Array.new(100, 50))

    expect(growth).to eq(100)
    expect(passes).to eq((described_class::MAX_WARMUP_ROUNDS + 1) * 2)
  end

  it "does not count pages the GC heap grows by but holds no live object on" do
    growth, = probe_over([0, 0, 16_000], pages: [0, 0, 16_000])

    expect(growth).to eq(0)
  end

  it "counts what live objects take, alongside pages the heap grows by" do
    growth, = probe_over(Array.new(20, 50) + [16_050, 50], pages: Array.new(20, 0) + [16_000])

    expect(growth).to eq(100)
  end

  it "counts growth in full in a round where the heap gives pages back" do
    costs = Array.new(20, 50) + [50 - 16_000] + Array.new(79, 50)
    growth, = probe_over(costs, pages: Array.new(20, 0) + [-16_000])

    expect(growth).to eq(100)
  end

  it "counts growth outside the heap in a round where objects that were live before it are freed" do
    growth, = probe_over(Array.new(100, 50), live: Array.new(100, -50))

    expect(growth).to eq(100)
  end

  it "counts objects kept on room the heap already had spare, which does not grow the process" do
    growth, = probe_over([], live: Array.new(100, 50))

    expect(growth).to eq(100)
  end

  # What a pass leaves behind is freed by the next collection, except that the
  # objects of the last pass before a collection survive it and go only at
  # the collection after that one.
  it "does not count the objects the last pass leaves behind, which outlive one collection" do
    heap = { live_kb: 40_000, since_collection_kb: 0, last_pass_kb: 0, survivors_kb: 0 }
    collector = lambda do
      heap[:live_kb] -= heap[:survivors_kb] + heap[:since_collection_kb] - heap[:last_pass_kb]
      heap.merge!(survivors_kb: heap[:last_pass_kb], since_collection_kb: 0, last_pass_kb: 0)
    end
    probe = described_class.new(iterations: 3, settled_below_kb: 10, reader: -> { 1000 }, collector: collector,
                                heap_reader: -> { { pages_kb: 50_000, live_kb: heap[:live_kb] } })

    growth = probe.call do
      heap[:live_kb] += 100
      heap.merge!(since_collection_kb: heap[:since_collection_kb] + 100, last_pass_kb: 100)
    end

    expect(growth).to eq(0)
  end

  it "runs the block the given number of times per round" do
    _, passes = probe_over([], iterations: 7)

    expect(passes).to eq(14)
  end

  it "collects garbage before each of the three readings of a round" do
    collections = 0
    probe = described_class.new(iterations: 1, settled_below_kb: 10, reader: -> { 1 }, collector: -> { collections += 1 })

    probe.call { nil }

    expect(collections).to eq(6)
  end

  it "reads real memory by default" do
    growth = described_class.new(iterations: 1, settled_below_kb: 1_000_000).call { nil }

    expect(growth).to be_a(Integer)
  end

  it "reads the live objects of the real GC heap by default, as the GC counts them" do
    skip "GC.stat_heap counts live slots per heap from Ruby 4.0" unless GC.stat_heap(0).key?(:heap_live_slots)

    GC.start
    heap = described_class::DEFAULT_HEAP_READER.call
    counted_kb = GC.stat_heap.each_value.sum { |stats| stats[:heap_live_slots] * stats[:slot_size] } / 1024

    expect(heap[:live_kb]).to be_within(64).of(counted_kb)
  end

  it "reads objects the process keeps as live, on pages of the heap" do
    GC.start
    before = described_class::DEFAULT_HEAP_READER.call
    retained = Array.new(200_000) { Object.new }
    GC.start
    after = described_class::DEFAULT_HEAP_READER.call
    retained_kb = retained.size * GC::INTERNAL_CONSTANTS.fetch(:BASE_SLOT_SIZE) / 1024
    spare_gained_kb = (after[:pages_kb] - after[:live_kb]) - (before[:pages_kb] - before[:live_kb])

    expect(after[:live_kb] - before[:live_kb]).to be >= retained_kb
    expect(spare_gained_kb).to be < retained_kb / 2
  end

  # Arrays small enough to live in their slots: a larger one's buffer is
  # malloc'd outside the GC heap, and the process may keep that after it is
  # freed. The heap's pages grow from round to round all the same.
  it "reads close to no growth for a block that only builds a large short-lived structure" do
    probe = described_class.new(iterations: 20, settled_below_kb: 2_560)

    growth = probe.call { Array.new(3_000) { Array.new(50) { "g" * 30 } } }

    expect(growth).to be_within(1_024).of(0)
  end
end
