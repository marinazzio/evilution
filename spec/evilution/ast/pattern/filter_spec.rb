# frozen_string_literal: true

require "prism"
require "evilution/ast/pattern/filter"

RSpec.describe Evilution::AST::Pattern::Filter do
  def parse_node(code)
    Prism.parse(code).value.statements.body[0]
  end

  describe "#skip?" do
    it "returns false when no patterns given" do
      filter = described_class.new([])
      node = parse_node("foo()")

      expect(filter.skip?(node)).to be false
    end

    it "returns true when node matches a pattern" do
      filter = described_class.new(["call{name=log}"])
      node = parse_node("log()")

      expect(filter.skip?(node)).to be true
    end

    it "returns false when node does not match" do
      filter = described_class.new(["call{name=log}"])
      node = parse_node("info()")

      expect(filter.skip?(node)).to be false
    end

    it "matches any of multiple patterns" do
      filter = described_class.new([
                                     "call{name=log}",
                                     "call{name=debug}"
                                   ])

      expect(filter.skip?(parse_node("log()"))).to be true
      expect(filter.skip?(parse_node("debug()"))).to be true
      expect(filter.skip?(parse_node("info()"))).to be false
    end

    it "matches nested patterns" do
      filter = described_class.new(["call{name=info, receiver=call{name=logger}}"])
      node = parse_node("logger.info")

      expect(filter.skip?(node)).to be true
    end

    it "rejects when nested pattern does not match" do
      filter = described_class.new(["call{name=info, receiver=call{name=logger}}"])
      node = parse_node("foo.info")

      expect(filter.skip?(node)).to be false
    end
  end

  describe "#skipped_count" do
    it "starts at zero" do
      filter = described_class.new(["call{name=log}"])

      expect(filter.skipped_count).to eq(0)
    end

    it "increments on each skip" do
      filter = described_class.new(["call{name=log}"])
      node = parse_node("log()")

      filter.skip?(node)
      filter.skip?(node)

      expect(filter.skipped_count).to eq(2)
    end

    it "does not increment on non-matching nodes" do
      filter = described_class.new(["call{name=log}"])

      filter.skip?(parse_node("info()"))

      expect(filter.skipped_count).to eq(0)
    end
  end

  describe "#reset_count!" do
    it "resets the skipped count to zero" do
      filter = described_class.new(["call{name=log}"])
      filter.skip?(parse_node("log()"))

      filter.reset_count!

      expect(filter.skipped_count).to eq(0)
    end
  end
end
