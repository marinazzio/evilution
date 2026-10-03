# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ComparisonOperandSwap do
  def mutations_for(body, filter: nil)
    tmpfile = Tempfile.new(["comparison_operand_swap", ".rb"])
    tmpfile.write("class Sorter\n  def call(a, b, items)\n#{body}  end\nend\n")
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
    it "swaps the operands of a spaceship comparison" do
      muts = mutations_for("    a <=> b\n")

      expect(mutated_lines(muts)).to eq(["b <=> a"])
    end

    it "reverses the order of a sort block" do
      muts = mutations_for("    items.sort { |x, y| x.age <=> y.age }\n")

      expect(mutated_lines(muts)).to eq(["items.sort { |x, y| y.age <=> x.age }"])
    end

    it "swaps operands that are themselves expressions" do
      expect(mutated_lines(mutations_for("    a + 1 <=> b\n"))).to eq(["b <=> a + 1"])
      expect(mutated_lines(mutations_for("    [a, 1] <=> [b, 2]\n"))).to eq(["[b, 2] <=> [a, 1]"])
    end

    it "keeps the explicit method-call form" do
      muts = mutations_for("    a.<=>(b)\n")

      expect(mutated_lines(muts)).to eq(["b.<=>(a)"])
    end

    it "keeps the spacing around the operator" do
      muts = mutations_for("    a<=>b\n")

      expect(mutated_lines(muts)).to eq(["b<=>a"])
    end

    it "swaps nested comparisons independently" do
      muts = mutations_for("    (a <=> b) <=> items\n")

      expect(mutated_lines(muts)).to eq(["items <=> (a <=> b)", "(b <=> a) <=> items"])
    end

    it "leaves an explicit call without exactly one argument alone" do
      expect(mutations_for("    a.<=>\n")).to be_empty
      expect(mutations_for("    a.<=>(b, items)\n")).to be_empty
    end

    # Swapping identical operands would reproduce the original comparison.
    it "skips identical operands" do
      expect(mutations_for("    a <=> a\n")).to be_empty
    end

    # With safe navigation a nil receiver yields nil instead of comparing;
    # moving the other operand into that place changes what may be nil.
    it "leaves a safe-navigation comparison alone" do
      expect(mutations_for("    a&.<=>(b)\n")).to be_empty
    end

    # Ordering methods with two arguments are reversed by
    # ArgumentOrderPermutation; this operator only covers the spaceship.
    it "leaves other comparisons alone" do
      expect(mutations_for("    a < b\n")).to be_empty
      expect(mutations_for("    a == b\n")).to be_empty
      expect(mutations_for("    items.between?(a, b)\n")).to be_empty
      expect(mutations_for("    items.clamp(a, b)\n")).to be_empty
    end

    it "produces parseable mutations" do
      muts = mutations_for("    items.sort { |x, y| y <=> x }\n    a.<=>(b)\n    a + 1 <=> b\n")

      expect(muts.length).to eq(3)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "sets the operator name" do
      muts = mutations_for("    a <=> b\n")

      expect(muts.map(&:operator_name)).to eq(["comparison_operand_swap"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{receiver=local_variable_read{name=a}}"])

      muts = mutations_for("    a <=> b\n", filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
