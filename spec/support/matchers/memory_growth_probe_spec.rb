# frozen_string_literal: true

require_relative "memory_growth_probe"

RSpec.describe MemoryGrowthProbe do
  # A process whose memory is whatever the block has made of it: each pass
  # adds the next entry of `costs` (then nothing), so warm-up is a list that
  # tapers off and a leak is one that does not. Each pass also moves the live
  # objects and the spare room of the GC heap by the next entries of `live`
  # and `spare`; what that costs the process is up to `costs`.
  def probe_over(costs, iterations: 2, settled_below_kb: 10, live: [], spare: [])
    process = { rss: 1000, live_kb: 0, spare_kb: 0 }
    remaining = { rss: costs, live_kb: live, spare_kb: spare }.transform_values(&:dup)
    passes = 0
    block = lambda do
      passes += 1
      remaining.each { |key, entries| process[key] += entries.shift || 0 }
    end
    probe = described_class.new(iterations: iterations, settled_below_kb: settled_below_kb,
                                reader: -> { process[:rss] },
                                heap_reader: -> { process.slice(:live_kb, :spare_kb) }, collector: -> {})
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

  it "does not count room the GC heap grows by but holds no live object in" do
    growth, = probe_over([0, 0, 16_000], spare: [0, 0, 16_000])

    expect(growth).to eq(0)
  end

  it "counts what live objects take, alongside the spare room the heap grows by" do
    growth, = probe_over(Array.new(20, 50) + [16_050, 50], spare: Array.new(20, 0) + [16_000])

    expect(growth).to eq(100)
  end

  it "counts growth in full in a round where the heap gives spare room back" do
    growth, = probe_over(Array.new(100, 50), spare: Array.new(20, 0) + [-16_000])

    expect(growth).to eq(100)
  end

  it "counts objects kept on room the heap already had spare, which does not grow the process" do
    growth, = probe_over([], live: Array.new(100, 50), spare: Array.new(100, -50))

    expect(growth).to eq(100)
  end

  it "runs the block the given number of times per round" do
    _, passes = probe_over([], iterations: 7)

    expect(passes).to eq(14)
  end

  it "collects garbage before each reading" do
    collections = 0
    probe = described_class.new(iterations: 1, settled_below_kb: 10, reader: -> { 1 }, collector: -> { collections += 1 })

    probe.call { nil }

    expect(collections).to eq(4)
  end

  it "reads real memory by default" do
    growth = described_class.new(iterations: 1, settled_below_kb: 1_000_000).call { nil }

    expect(growth).to be_a(Integer)
  end

  it "reads the real GC heap by default, its pages split into live objects and spare room" do
    GC.start
    pages_kb = GC.stat(:heap_allocated_pages) * GC::INTERNAL_CONSTANTS.fetch(:HEAP_PAGE_SIZE) / 1024
    heap = described_class::DEFAULT_HEAP_READER.call

    expect(heap[:live_kb]).to be_positive
    expect(heap[:spare_kb]).to be >= 0
    expect(heap[:live_kb] + heap[:spare_kb]).to be_within(1).of(pages_kb)
  end

  it "reads objects the process keeps as live, not as spare room" do
    GC.start
    before = described_class::DEFAULT_HEAP_READER.call
    retained = Array.new(200_000) { Object.new }
    GC.start
    after = described_class::DEFAULT_HEAP_READER.call
    retained_kb = retained.size * GC::INTERNAL_CONSTANTS.fetch(:BASE_SLOT_SIZE) / 1024

    expect(after[:live_kb] - before[:live_kb]).to be >= retained_kb
    expect(after[:spare_kb] - before[:spare_kb]).to be < retained_kb / 2
  end
end
