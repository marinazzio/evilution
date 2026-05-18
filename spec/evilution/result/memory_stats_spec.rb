# frozen_string_literal: true

RSpec.describe Evilution::Result::MemoryStats do
  describe ".from_fields" do
    it "returns nil when every field is nil" do
      expect(described_class.from_fields).to be_nil
    end

    it "builds a real MemoryStats when only child_rss_kb is given" do
      stats = described_class.from_fields(child_rss_kb: 100)

      expect(stats).to be_a(described_class)
      expect(stats.child_rss_kb).to eq(100)
      expect(stats.memory_delta_kb).to be_nil
      expect(stats.parent_rss_kb).to be_nil
    end

    it "builds a real MemoryStats when only memory_delta_kb is given" do
      stats = described_class.from_fields(memory_delta_kb: 25)

      expect(stats).to be_a(described_class)
      expect(stats.memory_delta_kb).to eq(25)
    end

    it "builds a real MemoryStats when only parent_rss_kb is given" do
      stats = described_class.from_fields(parent_rss_kb: 50_000)

      expect(stats).to be_a(described_class)
      expect(stats.parent_rss_kb).to eq(50_000)
    end

    it "preserves all three fields when given together" do
      stats = described_class.from_fields(child_rss_kb: 100, memory_delta_kb: 25, parent_rss_kb: 50_000)

      expect(stats.child_rss_kb).to eq(100)
      expect(stats.memory_delta_kb).to eq(25)
      expect(stats.parent_rss_kb).to eq(50_000)
    end
  end

  describe "#initialize" do
    it "stores child_rss_kb" do
      expect(described_class.new(child_rss_kb: 100).child_rss_kb).to eq(100)
    end

    it "stores memory_delta_kb" do
      expect(described_class.new(memory_delta_kb: 25).memory_delta_kb).to eq(25)
    end

    it "stores parent_rss_kb" do
      expect(described_class.new(parent_rss_kb: 50_000).parent_rss_kb).to eq(50_000)
    end

    it "is frozen" do
      expect(described_class.new(child_rss_kb: 100)).to be_frozen
    end
  end
end
