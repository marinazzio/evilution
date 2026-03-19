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

    it "collects RSS samples at intervals" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000)

      check = described_class.new(iterations: 20, max_growth_kb: 50_000)
      check.run { nil }

      expect(check.samples.length).to be > 2
    end

    it "returns growth in kilobytes" do
      rss = 100_000
      allow(Evilution::Memory).to receive(:rss_kb) { rss }

      check = described_class.new(iterations: 10, max_growth_kb: 50_000)
      check.run { rss += 500 }

      expect(check.growth_kb).to eq(check.samples.last - check.samples.first)
    end

    it "includes growth_mb in result" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000)

      check = described_class.new(iterations: 10, max_growth_kb: 50_000)
      result = check.run { nil }

      expect(result).to have_key(:growth_mb)
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
