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

    it "does not leak an unterminated literal from a prior call" do
      normalizer.call(%(x = "never   closed))
      expect(normalizer.call("a   b")).to eq("a b")
    end

    it "closes a string literal at its terminating quote" do
      expect(normalizer.call(%("a"   then   b))).to eq(%("a" then b))
    end

    it "collapses whitespace after a closing quote within the same line" do
      expect(normalizer.call(%(call("hi")   and   stop))).to eq(%(call("hi") and stop))
    end

    it "treats an escaped closing quote as literal content, keeping the literal open" do
      expect(normalizer.call(%("a\\"   z"))).to eq(%("a\\"   z"))
    end

    it "ignores a trailing backslash at the end of an open literal" do
      expect(normalizer.call(%(y = "p\\))).to eq(%(y = "p\\))
    end

    it "applies the escape only to backslashes, not to every literal character" do
      expect(normalizer.call(%("a\\b   c"   d   e))).to eq(%("a\\b   c" d e))
    end

    it "keeps a single space between a word and a following quoted literal" do
      expect(normalizer.call(%(a "lit" b))).to eq(%(a "lit" b))
    end

    it "releases references to processed line after returning" do
      normalizer.call("a   b")

      expect(normalizer.instance_variable_get(:@chars)).to be_nil
      expect(normalizer.instance_variable_get(:@out)).to be_nil
    end
  end
end
