# frozen_string_literal: true

require_relative "memory_growth_probe"

RSpec.describe MemoryGrowthProbe do
  # A process whose memory is whatever the block has made of it: each pass
  # adds the next entry of `costs` (then nothing), so warm-up is a list that
  # tapers off and a leak is one that does not.
  def probe_over(costs, iterations: 2, settled_below_kb: 10)
    rss = 1000
    remaining = costs.dup
    passes = 0
    block = lambda do
      passes += 1
      rss += remaining.shift || 0
    end
    probe = described_class.new(iterations: iterations, settled_below_kb: settled_below_kb,
                                reader: -> { rss }, collector: -> {})
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
end
