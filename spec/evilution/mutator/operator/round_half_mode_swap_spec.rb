# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RoundHalfModeSwap do
  def mutations_for(body, filter: nil)
    tmpfile = Tempfile.new(["round_half_mode_swap", ".rb"])
    tmpfile.write("class Price\n  def call(amount, mode)\n#{body}  end\nend\n")
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
    it "swaps half: :even for the other two modes" do
      muts = mutations_for("    amount.round(2, half: :even)\n")

      expect(mutated_lines(muts)).to eq(["amount.round(2, half: :up)", "amount.round(2, half: :down)"])
    end

    it "swaps half: :up for the other two modes" do
      muts = mutations_for("    amount.round(2, half: :up)\n")

      expect(mutated_lines(muts)).to eq(["amount.round(2, half: :even)", "amount.round(2, half: :down)"])
    end

    it "swaps half: :down for the other two modes" do
      muts = mutations_for("    amount.round(2, half: :down)\n")

      expect(mutated_lines(muts)).to eq(["amount.round(2, half: :up)", "amount.round(2, half: :even)"])
    end

    it "rewrites only the mode, whatever surrounds it" do
      muts = mutations_for("    total = amount&.round(half: :even, **{}).to_s + :even.to_s\n")

      expect(mutated_lines(muts)).to eq(
        ["total = amount&.round(half: :up, **{}).to_s + :even.to_s",
         "total = amount&.round(half: :down, **{}).to_s + :even.to_s"]
      )
    end

    it "swaps each round call of a nested expression" do
      muts = mutations_for("    amount.round(2, half: :up).fdiv(3).round(half: :down)\n")

      expect(mutated_lines(muts).length).to eq(4)
    end

    it "leaves a mode held in a variable alone" do
      expect(mutations_for("    amount.round(2, half: mode)\n")).to be_empty
    end

    it "leaves round without a mode alone" do
      expect(mutations_for("    amount.round(2)\n")).to be_empty
    end

    it "leaves a half: keyword of another method alone" do
      expect(mutations_for("    amount.floor(2, half: :even)\n")).to be_empty
    end

    it "produces parseable mutations" do
      muts = mutations_for("    amount.round(2, half: :even)\n")

      expect(muts.map(&:parse_status)).to eq(%i[ok ok])
    end

    it "sets the operator name" do
      muts = mutations_for("    amount.round(2, half: :even)\n")

      expect(muts.map(&:operator_name).uniq).to eq(["round_half_mode_swap"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=round}"])

      expect(mutations_for("    amount.round(2, half: :even)\n", filter: filter)).to be_empty
      expect(filter.skipped_count).to eq(2)
    end

    it "resets between calls on the same instance" do
      operator = described_class.new
      tmpfile = Tempfile.new(["round_half_mode_swap", ".rb"])
      tmpfile.write("def call(a) = a.round(half: :even)\n")
      tmpfile.flush
      subject = Evilution::AST::Parser.new.call(tmpfile.path).first

      expect([operator.call(subject).length, operator.call(subject).length]).to eq([2, 2])
    ensure
      tmpfile.close
      tmpfile.unlink
    end
  end
end
