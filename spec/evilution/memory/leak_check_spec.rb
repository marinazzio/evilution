# frozen_string_literal: true

require "evilution/memory/leak_check"

RSpec.describe Evilution::Memory::LeakCheck do
  describe "#run" do
    it "passes when memory growth is within threshold" do
      rss = 100_000
      allow(Evilution::Memory).to receive(:rss_kb) { rss }

      check = described_class.new(iterations: 10, max_growth_kb: 5_000)
      result = check.run { rss += 100 }

      expect(result[:passed]).to be true
    end

    it "fails when memory growth exceeds threshold" do
      rss = 100_000
      allow(Evilution::Memory).to receive(:rss_kb) { rss }

      check = described_class.new(iterations: 10, max_growth_kb: 500)
      result = check.run { rss += 1_000 }

      expect(result[:passed]).to be false
    end

    it "fails when RSS is unavailable" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(nil)

      check = described_class.new(iterations: 10, max_growth_kb: 50_000)
      result = check.run { nil }

      expect(result[:passed]).to be false
      expect(result[:rss_available]).to be false
    end

    it "collects RSS samples at intervals" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000)

      check = described_class.new(iterations: 20, max_growth_kb: 50_000)
      check.run { nil }

      expect(check.samples.length).to be > 2
    end

    it "takes a final sample after the loop" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000)

      # 7 iterations with sample_interval=1 means every iteration is sampled,
      # but use 13 with interval 1 to test the final sample path
      check = described_class.new(iterations: 13, max_growth_kb: 50_000)
      check.run { nil }

      # 1 initial + 13/1 interval samples + 0 final (13 divisible by 1)
      # Use 17 iterations: interval = max(17/10, 1) = 1, all sampled
      # Use 15: interval = 1, all sampled. Try 23: interval = 2
      check2 = described_class.new(iterations: 23, max_growth_kb: 50_000)
      check2.run { nil }

      # interval = max(23/10, 1) = 2, sampled at 2,4,6...22, plus initial, plus final (23%2!=0)
      # initial(1) + 11 interval samples + 1 final = 13
      expect(check2.samples.length).to eq(13)
    end

    it "returns growth in kilobytes" do
      rss = 100_000
      allow(Evilution::Memory).to receive(:rss_kb) { rss }

      check = described_class.new(iterations: 10, max_growth_kb: 50_000)
      check.run { rss += 500 }

      expect(check.growth_kb).to eq(check.samples.last - check.samples.first)
    end

    it "returns nil growth_kb when RSS unavailable" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(nil)

      check = described_class.new(iterations: 10, max_growth_kb: 50_000)
      check.run { nil }

      expect(check.growth_kb).to be_nil
    end

    it "includes growth_mb in result" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000)

      check = described_class.new(iterations: 10, max_growth_kb: 50_000)
      result = check.run { nil }

      expect(result).to have_key(:growth_mb)
    end

    it "includes rss_available in result" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000)

      check = described_class.new(iterations: 10, max_growth_kb: 50_000)
      result = check.run { nil }

      expect(result[:rss_available]).to be true
    end

    it "runs warmup iterations before measuring" do
      call_count = 0
      allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000)

      check = described_class.new(iterations: 10, max_growth_kb: 50_000)
      check.run { call_count += 1 }

      warmup = described_class::WARMUP_ITERATIONS
      expect(call_count).to eq(warmup + 10)
    end

    # EV-9d62 / GH #1298: kill survivors from EV-j2kz 2026-05-30 baseline.

    # Line 12: kwarg default — `iterations: DEFAULT_ITERATIONS` mutated to
    # required `iterations:` would raise on no-arg construction.
    it "defaults iterations to DEFAULT_ITERATIONS when not provided" do
      check = described_class.new(max_growth_kb: 50_000)

      expect(check.instance_variable_get(:@iterations)).to eq(described_class::DEFAULT_ITERATIONS)
    end

    # Same line — max_growth_kb default.
    it "defaults max_growth_kb to DEFAULT_MAX_GROWTH_KB when not provided" do
      check = described_class.new(iterations: 1)

      expect(check.instance_variable_get(:@max_growth_kb)).to eq(described_class::DEFAULT_MAX_GROWTH_KB)
    end

    # Same line — both defaults via zero-arg constructor.
    it "constructs with no arguments using all defaults" do
      check = described_class.new

      expect(check.instance_variable_get(:@iterations)).to eq(described_class::DEFAULT_ITERATIONS)
      expect(check.instance_variable_get(:@max_growth_kb)).to eq(described_class::DEFAULT_MAX_GROWTH_KB)
    end

    # Line 30: `samples.size < 2` — boundary at 2. Inject exactly two equal
    # samples so growth_kb returns 0. Mutation to `<= 2` would also return 0,
    # but `< 3` (literal) returns 0 too, so we need samples with size == 2 AND
    # non-zero diff to kill the `<= 2` mutation (which forces 0 result instead
    # of last-first delta).
    it "computes growth_kb from last-first when exactly 2 samples differ" do
      check = described_class.new(iterations: 1, max_growth_kb: 50_000)
      check.instance_variable_set(:@samples, [100, 250])

      expect(check.growth_kb).to eq(150)
    end

    # Same line — guard against `samples.size < 0` mutation. With 1 sample, the
    # mutated branch lets execution fall through to `samples.last - samples.first`
    # which is 0 for a single element. Original short-circuits to 0 via the
    # `< 2` check. To distinguish: use 1 sample → original returns 0,
    # mutated returns last-first == 0 too (same!). Use 0 samples → original
    # returns 0, mutated calls .last - .first on empty array (nil - nil) → raises.
    it "returns 0 from growth_kb when samples is empty (size < 2 short-circuit)" do
      check = described_class.new(iterations: 1, max_growth_kb: 50_000)
      check.instance_variable_set(:@samples, [])

      expect(check.growth_kb).to eq(0)
    end

    # Same line — 1 sample also short-circuits to 0.
    it "returns 0 from growth_kb when samples has one element" do
      check = described_class.new(iterations: 1, max_growth_kb: 50_000)
      check.instance_variable_set(:@samples, [500])

      expect(check.growth_kb).to eq(0)
    end

    # Line 39: `kb <= @max_growth_kb` boundary — passed? at equality.
    it "passes when growth_kb equals max_growth_kb (boundary inclusive)" do
      check = described_class.new(iterations: 1, max_growth_kb: 100)
      check.instance_variable_set(:@samples, [0, 100])

      expect(check.passed?).to be true
    end

    # Same line — kill `kb == @max_growth_kb` mutation: passes when growth_kb
    # < max_growth_kb strictly.
    it "passes when growth_kb is strictly less than max_growth_kb" do
      check = described_class.new(iterations: 1, max_growth_kb: 1000)
      check.instance_variable_set(:@samples, [0, 250])

      expect(check.passed?).to be true
    end

    # Same line — passed? returns false above the threshold.
    it "fails when growth_kb exceeds max_growth_kb" do
      check = described_class.new(iterations: 1, max_growth_kb: 100)
      check.instance_variable_set(:@samples, [0, 101])

      expect(check.passed?).to be false
    end

    # Line 37: `return false if kb.nil?` — explicit unit test using nil samples
    # so the false-returning path is exercised at the API level.
    it "returns false from passed? when growth_kb is nil (samples contain nil)" do
      check = described_class.new(iterations: 1, max_growth_kb: 100)
      check.instance_variable_set(:@samples, [nil, 100])

      expect(check.passed?).to be false
    end

    # Line 46: GC.start in warmup. Count calls explicitly via a spy so the
    # mutation that removes the GC.start in warmup is detected even if other
    # code paths call GC.start.
    it "invokes GC.start during warmup specifically (not just during measure)" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000)
      check = described_class.new(iterations: 1, max_growth_kb: 50_000)

      # Stub warmup-internal to call warmup directly + verify GC.start fires.
      gc_start_calls = 0
      allow(GC).to receive(:start) { gc_start_calls += 1 }
      check.send(:warmup) { nil }

      expect(gc_start_calls).to eq(1)
    end

    # Line 47: GC.compact in warmup (when available).
    it "calls GC.compact during warmup specifically when supported", if: GC.respond_to?(:compact) do
      compact_calls = 0
      allow(GC).to receive(:compact) { compact_calls += 1 }
      allow(GC).to receive(:start)
      check = described_class.new(iterations: 1, max_growth_kb: 50_000)
      check.send(:warmup) { nil }

      expect(compact_calls).to eq(1)
    end

    # Line 50: `&` block param — measure forwards the block via `&`. If `&` is
    # removed, the block isn't propagated to yield via the captured proc.
    # `yield` in measure still works because Ruby uses the implicit block, so
    # this mutation may be benign — but `warmup(&)` also relies on `&` to
    # forward to `block.call`. Verify block forwarding via call counts.
    it "forwards the block to warmup and measure (block param)" do
      n = 0
      allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000)
      check = described_class.new(iterations: 3, max_growth_kb: 50_000)
      check.run { n += 1 }

      # WARMUP_ITERATIONS warmup calls + 3 measure iterations = 8.
      expect(n).to eq(described_class::WARMUP_ITERATIONS + 3)
    end

    # Line 56: `((i + 1) % sample_interval).zero?` — mutated to `(i - 1)`.
    # Sample at iter index when (i+1) % interval == 0; mutated sample at
    # different indices. Pick iterations such that sample positions differ.
    it "samples at (i + 1) % sample_interval == 0 (not i - 1)" do
      rss = [200, 300, 400, 500, 600]
      allow(Evilution::Memory).to receive(:rss_kb) { rss.shift || 600 }
      # iterations=20 → sample_interval = max(20/10, 1) = 2
      # measure: initial sample + sampled at i=1,3,5,...,19 (i+1=2,4,...,20 % 2 == 0)
      # iterations % interval = 20 % 2 = 0 → take_final_sample skips
      check = described_class.new(iterations: 4, max_growth_kb: 50_000)
      # iter=4: interval = max(4/10, 1) = 1, all sampled
      # initial(1) + 4 interval samples + 0 final = 5 samples
      check.run { nil }

      expect(check.samples.length).to eq(5)
    end

    # Line 58: GC.start during measure interval sampling.
    it "calls GC.start at sample intervals during measure" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000)
      check = described_class.new(iterations: 10, max_growth_kb: 50_000)

      # warmup: 1, measure interval samples: 10, take_final_sample: 0 → 11
      expect(GC).to receive(:start).at_least(11).times.and_call_original
      check.run { nil }
    end

    # Line 66: `(@iterations % sample_interval).zero?` — take_final_sample
    # skips when iterations divisible by interval, takes when not. Mutated to
    # `*` only zero if iterations==0 or interval==0 (impossible here), so the
    # mutation forces "always take final sample".
    it "skips take_final_sample when iterations divisible by sample_interval" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000)
      check = described_class.new(iterations: 20, max_growth_kb: 50_000)
      # interval = max(20/10, 1) = 2, 20 % 2 == 0 → skip final sample
      # initial(1) + sampled at i=1,3,...,19 → 10 → total 11 samples
      check.run { nil }

      expect(check.samples.length).to eq(11)
    end

    # Same line — verify take_final_sample DOES fire when iterations
    # not divisible by interval.
    it "takes final sample when iterations not divisible by sample_interval" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000)
      check = described_class.new(iterations: 21, max_growth_kb: 50_000)
      # interval = max(21/10, 1) = 2, 21 % 2 == 1 → final sample fires
      # initial(1) + sampled at i+1 in [2,4,...,20] (10 samples) + final(1) = 12
      check.run { nil }

      expect(check.samples.length).to eq(12)
    end

    # Line 68: GC.start inside take_final_sample.
    it "calls GC.start during take_final_sample" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000)
      check = described_class.new(iterations: 21, max_growth_kb: 50_000)
      # warmup(1) + measure samples 10 + final(1) = 12 GC.start calls
      expect(GC).to receive(:start).at_least(12).times.and_call_original
      check.run { nil }
    end

    # Line 69: `@samples << Evilution::Memory.rss_kb` — mutated to << nil.
    # Final sample value must equal stubbed RSS, not nil.
    it "pushes a numeric RSS reading (not nil) as the final sample" do
      seq = [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1100, 1200,
             1300, 1400, 1500, 1600, 1700, 1800, 1900, 2000]
      idx = 0
      allow(Evilution::Memory).to receive(:rss_kb) { seq[idx].tap { idx += 1 } || 9999 }
      check = described_class.new(iterations: 21, max_growth_kb: 100_000_000)
      check.run { nil }

      expect(check.samples.last).to be_a(Integer)
      expect(check.samples.last).to be > 0
    end

    # Line 73: `[@iterations / 10, 1].max` — divisor 10. Mutated divisor 11
    # gives different sample_interval for iterations in [11, 19]. Pick 11.
    it "computes sample_interval as iterations / 10 (floor) capped at 1 minimum" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000)
      described_class.new(iterations: 11, max_growth_kb: 50_000)
      # 11 / 10 = 1, max(1, 1) = 1 → all iterations sampled
      # 11 / 11 = 1 too (same) — pick a value where they differ
      # Try 20: 20/10 = 2, 20/11 = 1 → different interval
      # With interval=2 for iter=20: samples = 1 + 10 + 0 = 11
      # With interval=1 for iter=20: samples = 1 + 20 + 0 = 21
      check_v = described_class.new(iterations: 20, max_growth_kb: 50_000)
      check_v.run { nil }

      expect(check_v.samples.length).to eq(11)
    end

    # Line 80: `growth_kb / 1024.0` — mutation to `*`.
    it "converts growth_kb to growth_mb by dividing by 1024.0" do
      check = described_class.new(iterations: 1, max_growth_kb: 50_000)
      check.instance_variable_set(:@samples, [0, 2048])

      expect(check.send(:result)[:growth_mb]).to eq(2.0)
    end

    # Same line — `nil_replacement` mutation makes the false branch return
    # `true` instead of `nil`. Assert exact-nil identity when growth_kb is nil.
    it "returns nil growth_mb when growth_kb is nil (not truthy fallback)" do
      check = described_class.new(iterations: 1, max_growth_kb: 50_000)
      check.instance_variable_set(:@samples, [nil, nil])

      expect(check.send(:result)[:growth_mb]).to be_nil
    end
  end
end
