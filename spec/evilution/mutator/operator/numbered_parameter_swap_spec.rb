# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::NumberedParameterSwap do
  def mutations_for(body, filter: nil)
    tmpfile = Tempfile.new(["numbered_parameter_swap", ".rb"])
    tmpfile.write("class Mapper\n  def call(pairs)\n#{body}  end\nend\n")
    tmpfile.flush
    subject = Evilution::AST::Parser.new.call(tmpfile.path).first
    described_class.new.call(subject, filter: filter)
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  # The line each mutation rewrote.
  def mutated_lines(muts)
    muts.map { |m| m.mutated_source.lines[m.line - 1].strip }
  end

  describe "#call" do
    it "swaps the two numbered parameters of a block" do
      muts = mutations_for("    pairs.map { _1 - _2 }\n")

      expect(mutated_lines(muts)).to eq(["pairs.map { _2 - _1 }"])
    end

    it "swaps every read of both parameters" do
      muts = mutations_for("    pairs.map { _1.fetch(_2) + _1.size - _2 }\n")

      expect(mutated_lines(muts)).to eq(["pairs.map { _2.fetch(_1) + _2.size - _1 }"])
    end

    it "swaps the parameters of a do block spread over several lines" do
      muts = mutations_for("    pairs.each do\n      store(_1)\n      log(_2)\n    end\n")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("    pairs.each do\n      store(_2)\n      log(_1)\n    end\n")
    end

    it "swaps the parameters of a lambda" do
      muts = mutations_for("    -> { _1 - _2 }\n")

      expect(mutated_lines(muts)).to eq(["-> { _2 - _1 }"])
    end

    it "swaps each adjacent pair of three parameters" do
      muts = mutations_for("    pairs.map { [_1, _2, _3] }\n")

      expect(mutated_lines(muts)).to eq(
        ["pairs.map { [_2, _1, _3] }", "pairs.map { [_1, _3, _2] }"]
      )
    end

    # Only parameters the body reads are swapped with each other. Bringing in
    # an unread one would change how many values the block takes, which is a
    # different mutation from reordering them.
    it "swaps the parameters that are read when one between them is not" do
      muts = mutations_for("    pairs.map { _1 - _3 }\n")

      expect(mutated_lines(muts)).to eq(["pairs.map { _3 - _1 }"])
    end

    it "orders the pairs by parameter number, not by where they are read" do
      muts = mutations_for("    pairs.map { [_3, _1, _2] }\n")

      expect(mutated_lines(muts)).to eq(
        ["pairs.map { [_3, _2, _1] }", "pairs.map { [_2, _1, _3] }"]
      )
    end

    # The condition of a modifier is visited before the statement it guards,
    # although it is written after it.
    it "swaps parameters read on both sides of a modifier" do
      muts = mutations_for("    pairs.map { _1 if _2 }\n")

      expect(mutated_lines(muts)).to eq(["pairs.map { _2 if _1 }"])
    end

    it "leaves other locals read in the block alone" do
      muts = mutations_for("    scale = 2\n    pairs.map { (_1 - _2) * scale + pairs.size }\n")

      expect(mutated_lines(muts)).to eq(["pairs.map { (_2 - _1) * scale + pairs.size }"])
    end

    it "emits nothing when a single numbered parameter is read" do
      expect(mutations_for("    pairs.map { _1 * 2 }\n")).to be_empty
      expect(mutations_for("    pairs.map { _2 * 2 }\n")).to be_empty
    end

    it "emits nothing for an implicit it parameter" do
      muts = mutations_for("    pairs.map { it * 2 }\n")

      expect(muts).to be_empty
    end

    it "emits nothing for explicit parameters" do
      muts = mutations_for("    pairs.map { |left, right| left - right }\n")

      expect(muts).to be_empty
    end

    it "emits nothing for a block without parameters" do
      muts = mutations_for("    pairs.each { touch }\n")

      expect(muts).to be_empty
    end

    it "swaps the parameters of a block nested in an explicit one" do
      muts = mutations_for("    pairs.each { |group| group.map { _1 - _2 } }\n")

      expect(mutated_lines(muts)).to eq(["pairs.each { |group| group.map { _2 - _1 } }"])
    end

    it "swaps the parameters of a block nested in a lambda" do
      muts = mutations_for("    -> { pairs.map { _1 - _2 } }\n")

      expect(mutated_lines(muts)).to eq(["-> { pairs.map { _2 - _1 } }"])
    end

    # A method defined inside the block opens its own scope; the numbered
    # parameters read there belong to its blocks.
    it "keeps the numbered parameters of a method defined in the block apart" do
      muts = mutations_for("    pairs.map do\n      define(_1, _2)\n      def inner(xs) = xs.map { _1 - _2 }\n    end\n")

      expect(muts.map(&:mutated_source)).to contain_exactly(
        a_string_including("define(_2, _1)\n      def inner(xs) = xs.map { _1 - _2 }"),
        a_string_including("define(_1, _2)\n      def inner(xs) = xs.map { _2 - _1 }")
      )
    end

    it "produces parseable mutations" do
      muts = mutations_for("    pairs.map { [_1, _2, _3] }\n    -> { _1 - _2 }\n")

      expect(muts.map(&:parse_status)).to eq(%i[ok ok ok])
    end

    it "sets the operator name" do
      muts = mutations_for("    pairs.map { _1 - _2 }\n")

      expect(muts.map(&:operator_name)).to eq(["numbered_parameter_swap"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["block"])

      muts = mutations_for("    pairs.map { _1 - _2 }\n", filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
