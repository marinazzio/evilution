# frozen_string_literal: true

require "evilution/line_set"

RSpec.describe Evilution::LineSet do
  describe ".new" do
    it "keeps its ranges sorted by their first line" do
      expect(described_class.new([9..9, 2..4]).ranges).to eq([2..4, 9..9])
    end

    it "merges ranges that overlap" do
      expect(described_class.new([2..5, 4..8]).ranges).to eq([2..8])
    end

    it "merges ranges that touch" do
      expect(described_class.new([2..4, 5..6]).ranges).to eq([2..6])
    end

    it "keeps ranges apart that a line separates" do
      expect(described_class.new([2..4, 6..6]).ranges).to eq([2..4, 6..6])
    end

    it "swallows a range that another one contains" do
      expect(described_class.new([2..10, 4..5]).ranges).to eq([2..10])
    end

    it "merges a range into the last one kept, not the first" do
      expect(described_class.new([1..2, 5..6, 7..8]).ranges).to eq([1..2, 5..8])
    end

    it "merges into an open-ended range" do
      expect(described_class.new([3..Float::INFINITY, 1..4]).ranges).to eq([1..Float::INFINITY])
    end

    it "drops ranges that hold no line" do
      expect(described_class.new([5..4, 7..7]).ranges).to eq([7..7])
    end

    it "is frozen, with frozen ranges" do
      set = described_class.new([1..2])

      expect(set).to be_frozen
      expect(set.ranges).to be_frozen
    end
  end

  describe ".wrap" do
    it "turns a Range into a set of that range" do
      expect(described_class.wrap(3..7).ranges).to eq([3..7])
    end

    it "returns a set as it is" do
      set = described_class.new([1..2])

      expect(described_class.wrap(set)).to equal(set)
    end
  end

  describe "#cover?" do
    let(:set) { described_class.new([2..4, 9..9]) }

    it "covers a line of one of its ranges" do
      expect(set.cover?(3)).to be(true)
      expect(set.cover?(9)).to be(true)
    end

    it "does not cover a line between its ranges" do
      expect(set.cover?(5)).to be(false)
    end

    it "does not cover lines outside every range" do
      expect(set.cover?(1)).to be(false)
      expect(set.cover?(10)).to be(false)
    end
  end

  describe "#overlap?" do
    let(:set) { described_class.new([5..6, 20..22]) }

    it "overlaps lines that reach into one of its ranges" do
      expect(set.overlap?(1, 5)).to be(true)
      expect(set.overlap?(22, 30)).to be(true)
    end

    it "overlaps lines that span a whole range" do
      expect(set.overlap?(10, 25)).to be(true)
    end

    it "does not overlap lines that fall between its ranges" do
      expect(set.overlap?(7, 19)).to be(false)
    end

    it "does not overlap lines before its first or after its last range" do
      expect(set.overlap?(1, 4)).to be(false)
      expect(set.overlap?(23, 40)).to be(false)
    end

    it "overlaps every line past the start of an open-ended range" do
      expect(described_class.new([5..Float::INFINITY]).overlap?(900, 901)).to be(true)
    end
  end

  describe "#&" do
    let(:set) { described_class.new([2..4, 8..12]) }

    it "keeps the lines a Range shares with it" do
      expect((set & (3..9)).ranges).to eq([3..4, 8..9])
    end

    it "keeps the lines another set shares with it" do
      expect((set & described_class.new([1..2, 10..20])).ranges).to eq([2..2, 10..12])
    end

    it "is empty when nothing is shared" do
      expect(set & (5..7)).to be_empty
    end

    it "keeps every line from the start of an open-ended range" do
      expect((set & (10..Float::INFINITY)).ranges).to eq([10..12])
    end
  end

  describe "#empty?" do
    it "is empty without ranges" do
      expect(described_class.new([])).to be_empty
    end

    it "is not empty with a range" do
      expect(described_class.new([1..1])).not_to be_empty
    end
  end

  describe "#==" do
    it "equals a set of the same lines" do
      expect(described_class.new([1..2, 3..3])).to eq(described_class.new([1..3]))
    end

    it "does not equal a set of other lines" do
      expect(described_class.new([1..2])).not_to eq(described_class.new([1..3]))
    end

    it "does not equal a Range" do
      expect(described_class.new([1..2])).not_to eq(1..2)
    end

    it "hashes like a set of the same lines" do
      expect(described_class.new([1..2]).hash).to eq(described_class.new([1..2]).hash)
      expect(described_class.new([1..2]).hash).to be_a(Integer)
    end

    it "hashes apart from a set of other lines" do
      expect(described_class.new([1..2]).hash).not_to eq(described_class.new([1..3]).hash)
    end

    it "is eql? to a set of the same lines, so it finds its key in a Hash" do
      expect(described_class.new([1..2])).to eql(described_class.new([1..2]))
      expect({ described_class.new([1..2]) => true }).to have_key(described_class.new([1..2]))
    end
  end

  describe "#to_s" do
    it "spells its ranges the way the command line takes one" do
      expect(described_class.new([2..4, 9..9]).to_s).to eq("2-4,9")
    end

    it "spells an open-ended range with no end" do
      expect(described_class.new([3..Float::INFINITY]).to_s).to eq("3-")
    end
  end
end
