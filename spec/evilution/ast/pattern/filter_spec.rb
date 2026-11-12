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

    it "matches bang, predicate and operator method names" do
      filter = described_class.new(["call{name=strip_sources!|valid?}", "call{name=<=>}", "call{name='|'}"])

      expect(filter.skip?(parse_node("strip_sources!"))).to be true
      expect(filter.skip?(parse_node("record.valid?"))).to be true
      expect(filter.skip?(parse_node("a <=> b"))).to be true
      expect(filter.skip?(parse_node("a | b"))).to be true
      expect(filter.skip?(parse_node("strip_sources"))).to be false
      expect(filter.skip?(parse_node("a <= b"))).to be false
    end

    it "rejects when nested pattern does not match" do
      filter = described_class.new(["call{name=info, receiver=call{name=logger}}"])
      node = parse_node("foo.info")

      expect(filter.skip?(node)).to be false
    end

    context "with the source the node was parsed from" do
      let(:source) { "class Order\n  validates :rush, if: :paid\nend\n" }
      let!(:symbol) { Prism.parse(source).value.statements.body.first.body.body.first.arguments.arguments.first }

      it "returns true when an ancestor matches a pattern" do
        filter = described_class.new(["call{name=validates}"])

        expect(filter.skip?(symbol, source: source)).to be true
      end

      it "matches ancestors up to the top of the source" do
        filter = described_class.new(["class{constant_path=constant_read{name=Order}}"])

        expect(filter.skip?(symbol, source: source)).to be true
      end

      it "returns false when neither the node nor an ancestor matches" do
        filter = described_class.new(["call{name=log}", "keyword_hash"])

        expect(filter.skip?(symbol, source: source)).to be false
      end

      it "counts a mutation once when the node and several ancestors match" do
        filter = described_class.new(["_", "call{name=validates}", "arguments"])

        filter.skip?(symbol, source: source)

        expect(filter.skipped_count).to eq(1)
      end

      it "finds the ancestors in a copy of the source, and in the next source it is given" do
        filter = described_class.new(["call{name=validates}"])
        other_source = "validates(:a)\nlog(:b)\n"
        other = Prism.parse(other_source).value.statements.body

        expect(filter.skip?(symbol, source: source.dup)).to be true
        expect(filter.skip?(other[0].arguments.arguments.first, source: other_source)).to be true
        expect(filter.skip?(other[1].arguments.arguments.first, source: other_source)).to be false
        expect(filter.skip?(symbol, source: source)).to be true
      end

      it "does not parse the source when the node itself matches" do
        filter = described_class.new(["symbol"])

        expect(Prism).not_to receive(:parse)
        expect(filter.skip?(symbol, source: source)).to be true
      end

      it "does not parse the source when there are no patterns" do
        filter = described_class.new([])

        expect(Prism).not_to receive(:parse)
        expect(filter.skip?(symbol, source: source)).to be false
      end

      it "parses a source once for all the nodes checked in it" do
        filter = described_class.new(["call{name=log}"])
        allow(Prism).to receive(:parse).and_call_original

        2.times { filter.skip?(symbol, source: source) }
        filter.skip?(symbol, source: source.dup)

        expect(Prism).to have_received(:parse).once
      end
    end

    it "does not compare a source it was just given byte by byte" do
      filter = described_class.new(["call{name=log}"])
      source = "validates :rush\n".dup
      symbol = Prism.parse(source).value.statements.body.first.arguments.arguments.first
      filter.skip?(symbol, source: source)
      allow(source).to receive(:==).and_call_original

      filter.skip?(symbol, source: source)

      expect(source).not_to have_received(:==)
    end

    it "tests the node alone when no source is given" do
      filter = described_class.new(["call{name=validates}"])
      symbol = parse_node("validates :rush").arguments.arguments.first

      expect(Prism).not_to receive(:parse)
      expect(filter.skip?(symbol)).to be false
    end

    it "keeps the patterns it was given as they are" do
      patterns = ["call{name=log}"].freeze

      expect { described_class.new(patterns) }.not_to raise_error
    end

    it "keeps how it matches to itself" do
      expect(described_class.new([]).private_methods(false)).to include(:matches?, :ancestors, :parent_index)
    end

    it "does not let the count be set from outside" do
      expect(described_class.new([])).not_to respond_to(:skipped_count=)
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
