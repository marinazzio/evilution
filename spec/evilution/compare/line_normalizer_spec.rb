# frozen_string_literal: true

require "evilution/compare/line_normalizer"

RSpec.describe Evilution::Compare::LineNormalizer do
  subject(:normalizer) { described_class.new }

  describe "#call" do
    it "collapses runs of whitespace into single spaces" do
      expect(normalizer.call("a   b\t\tc")).to eq("a b c")
    end

    it "strips trailing whitespace" do
      expect(normalizer.call("foo bar   ")).to eq("foo bar")
    end

    it "drops leading whitespace" do
      expect(normalizer.call("   foo")).to eq("foo")
    end

    it "preserves whitespace inside double-quoted string literals" do
      expect(normalizer.call(%(x = "a   b"))).to eq(%(x = "a   b"))
    end

    it "preserves whitespace inside single-quoted string literals" do
      expect(normalizer.call(%(x = 'a   b'))).to eq(%(x = 'a   b'))
    end

    it "preserves escaped quote inside string literal" do
      expect(normalizer.call(%(x = "a\\"b"))).to eq(%(x = "a\\"b"))
    end

    it "is reusable across calls without state leakage" do
      normalizer.call("first  call")
      expect(normalizer.call("second   call")).to eq("second call")
    end
  end
end
