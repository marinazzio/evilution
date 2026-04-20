# frozen_string_literal: true

require "prism"
require "timeout"
require "evilution/source_ast_cache"

RSpec.describe Evilution::SourceAstCache do
  let(:cache) { described_class.new }

  describe "#fetch" do
    it "returns a Prism::ParseResult for a valid source string" do
      result = cache.fetch("a = 1\n")

      expect(result).to be_a(Prism::ParseResult)
      expect(result.failure?).to be false
    end

    it "parses identical source only once across repeated fetches" do
      source = "def foo; 1; end\n"
      call_count = 0
      original = Prism.method(:parse)
      allow(Prism).to receive(:parse) do |arg|
        call_count += 1
        original.call(arg)
      end

      cache.fetch(source)
      cache.fetch(source)

      expect(call_count).to eq(1)
    end

    it "parses different sources independently" do
      call_count = 0
      original = Prism.method(:parse)
      allow(Prism).to receive(:parse) do |arg|
        call_count += 1
        original.call(arg)
      end

      cache.fetch("a = 1\n")
      cache.fetch("b = 2\n")

      expect(call_count).to eq(2)
    end

    it "returns the identical (equal?) Prism::ParseResult on cache hit" do
      source = "x = 42\n"

      first = cache.fetch(source)
      second = cache.fetch(source)

      expect(second).to be(first)
    end

    it "caches failing parse results and returns the same object on repeat" do
      broken = "def broken(\n"
      call_count = 0
      original = Prism.method(:parse)
      allow(Prism).to receive(:parse) do |arg|
        call_count += 1
        original.call(arg)
      end

      first = cache.fetch(broken)
      second = cache.fetch(broken)

      expect(first.failure?).to be true
      expect(second).to be(first)
      expect(call_count).to eq(1)
    end
  end

  describe "LRU eviction" do
    it "evicts the least-recently-used entry when max_entries is exceeded" do
      c = described_class.new(max_entries: 2)
      sources = ["a = 1\n", "b = 2\n", "c = 3\n"]

      first_a = c.fetch(sources[0])
      c.fetch(sources[1])
      c.fetch(sources[2])

      call_count = 0
      original = Prism.method(:parse)
      allow(Prism).to receive(:parse) do |arg|
        call_count += 1
        original.call(arg)
      end

      re_a = c.fetch(sources[0])

      expect(re_a).not_to be(first_a)
      expect(call_count).to eq(1)
    end

    it "bumps an entry to most-recently-used on access so newer entries cannot evict it" do
      c = described_class.new(max_entries: 2)
      sources = ["a = 1\n", "b = 2\n", "c = 3\n"]

      first_a = c.fetch(sources[0])
      c.fetch(sources[1])
      c.fetch(sources[0]) # bumps a to MRU
      c.fetch(sources[2]) # evicts b

      call_count = 0
      original = Prism.method(:parse)
      allow(Prism).to receive(:parse) do |arg|
        call_count += 1
        original.call(arg)
      end

      re_a = c.fetch(sources[0])

      expect(re_a).to be(first_a)
      expect(call_count).to eq(0)
    end

    it "works with max_entries: 1" do
      c = described_class.new(max_entries: 1)

      first_a = c.fetch("a = 1\n")
      c.fetch("b = 2\n")

      call_count = 0
      original = Prism.method(:parse)
      allow(Prism).to receive(:parse) do |arg|
        call_count += 1
        original.call(arg)
      end

      re_a = c.fetch("a = 1\n")

      expect(re_a).not_to be(first_a)
      expect(call_count).to eq(1)
    end

    it "does not loop on max_entries: 0" do
      c = described_class.new(max_entries: 0)

      expect { Timeout.timeout(1) { c.fetch("a = 1\n") } }.not_to raise_error
    end

    it "does not loop on negative max_entries" do
      c = described_class.new(max_entries: -1)

      expect { Timeout.timeout(1) { c.fetch("a = 1\n") } }.not_to raise_error
    end
  end
end
