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
  end
end
