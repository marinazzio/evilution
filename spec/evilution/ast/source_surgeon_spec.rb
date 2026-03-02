# frozen_string_literal: true

RSpec.describe Evilution::AST::SourceSurgeon do
  describe ".apply" do
    it "replaces text at the given byte offset" do
      source = "age >= 18"
      result = described_class.apply(source, offset: 4, length: 2, replacement: ">")

      expect(result).to eq("age > 18")
    end

    it "handles replacement shorter than original" do
      source = "x == y"
      result = described_class.apply(source, offset: 2, length: 2, replacement: ">")

      expect(result).to eq("x > y")
    end

    it "handles replacement longer than original" do
      source = "x > y"
      result = described_class.apply(source, offset: 2, length: 1, replacement: ">=")

      expect(result).to eq("x >= y")
    end

    it "handles replacement at start of string" do
      source = "true && false"
      result = described_class.apply(source, offset: 0, length: 4, replacement: "false")

      expect(result).to eq("false && false")
    end

    it "handles replacement at end of string" do
      source = "x + 42"
      result = described_class.apply(source, offset: 4, length: 2, replacement: "0")

      expect(result).to eq("x + 0")
    end

    it "does not mutate the original string" do
      source = "age >= 18"
      described_class.apply(source, offset: 4, length: 2, replacement: ">")

      expect(source).to eq("age >= 18")
    end

    it "handles multi-line source" do
      source = "def foo\n  x >= 10\nend"
      result = described_class.apply(source, offset: 12, length: 2, replacement: ">")

      expect(result).to eq("def foo\n  x > 10\nend")
    end

    it "handles replacing with empty string" do
      source = "return 42"
      result = described_class.apply(source, offset: 6, length: 3, replacement: "")

      expect(result).to eq("return")
    end
  end
end
