# frozen_string_literal: true

RSpec.describe Evilution::Memory do
  describe ".rss_mb" do
    it "returns a positive float" do
      result = described_class.rss_mb
      expect(result).to be_a(Float)
      expect(result).to be > 0.0
    end

    it "returns a value in a reasonable range for a Ruby process" do
      result = described_class.rss_mb
      expect(result).to be_between(1.0, 4096.0)
    end
  end

  describe ".rss_kb" do
    it "returns a positive integer" do
      result = described_class.rss_kb
      expect(result).to be_a(Integer)
      expect(result).to be > 0
    end

    it "is consistent with rss_mb" do
      kb = described_class.rss_kb
      mb = described_class.rss_mb
      expect(mb).to be_within(1.0).of(kb / 1024.0)
    end
  end

  describe ".rss_kb_for" do
    it "returns RSS for the current process" do
      result = described_class.rss_kb_for(Process.pid)
      expect(result).to be_a(Integer)
      expect(result).to be > 0
    end

    it "returns nil for a nonexistent PID" do
      result = described_class.rss_kb_for(999_999_999)
      expect(result).to be_nil
    end
  end

  describe ".delta" do
    it "yields the block and returns [result, delta_kb]" do
      result, delta_kb = described_class.delta { 42 }
      expect(result).to eq(42)
      expect(delta_kb).to be_a(Integer)
    end

    it "measures memory change from an allocation" do
      _result, delta_kb = described_class.delta { Array.new(100_000) { "x" * 1000 } }
      # Allocating ~100MB of strings should show positive delta
      expect(delta_kb).to be > 0
    end
  end
end
