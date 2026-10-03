# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::IntegerDivisionToFdiv do
  def mutations_for(body, filter: nil)
    tmpfile = Tempfile.new(["integer_division_to_fdiv", ".rb"])
    tmpfile.write("class Ratio\n  def call(a, b, c)\n#{body}  end\nend\n")
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
    it "turns a division into fdiv" do
      muts = mutations_for("    a / b\n")

      expect(mutated_lines(muts)).to eq(["a.fdiv(b)"])
    end

    it "keeps a compound divisor inside the argument list" do
      muts = mutations_for("    a / (b + c)\n")

      expect(mutated_lines(muts)).to eq(["a.fdiv((b + c))"])
    end

    it "keeps simple receivers as they are" do
      expect(mutated_lines(mutations_for("    @total / b\n"))).to eq(["@total.fdiv(b)"])
      expect(mutated_lines(mutations_for("    items.size / b\n"))).to eq(["items.size.fdiv(b)"])
      expect(mutated_lines(mutations_for("    7 / b\n"))).to eq(["7.fdiv(b)"])
      expect(mutated_lines(mutations_for("    (a + b) / c\n"))).to eq(["(a + b).fdiv(c)"])
      expect(mutated_lines(mutations_for("    LIMIT / b\n"))).to eq(["LIMIT.fdiv(b)"])
    end

    # `.fdiv` binds tighter than any operator, so a compound receiver has to
    # be grouped to keep the whole expression as the dividend.
    it "parenthesises a compound receiver" do
      expect(mutated_lines(mutations_for("    a * b / c\n"))).to eq(["(a * b).fdiv(c)"])
      expect(mutated_lines(mutations_for("    -a / b\n"))).to eq(["(-a).fdiv(b)"])
      expect(mutated_lines(mutations_for("    [a, b] / c\n"))).to eq(["([a, b]).fdiv(c)"])
    end

    it "turns each division of a chain into fdiv" do
      muts = mutations_for("    a / b / c\n")

      expect(mutated_lines(muts)).to eq(["(a / b).fdiv(c)", "a.fdiv(b) / c"])
    end

    it "turns a division nested in another expression into fdiv" do
      muts = mutations_for("    a + b / c\n")

      expect(mutated_lines(muts)).to eq(["a + b.fdiv(c)"])
    end

    # Float division and fdiv agree, so the mutant would change nothing.
    it "skips a division with a float literal on either side" do
      expect(mutations_for("    a / 2.0\n")).to be_empty
      expect(mutations_for("    1.5 / a\n")).to be_empty
    end

    it "leaves other operators and division assignment alone" do
      expect(mutations_for("    a * b\n")).to be_empty
      expect(mutations_for("    a % b\n")).to be_empty
      expect(mutations_for("    a /= b\n")).to be_empty
    end

    it "leaves the explicit method-call form alone" do
      expect(mutations_for("    a./(b)\n")).to be_empty
    end

    it "produces parseable mutations" do
      muts = mutations_for("    a * b / c\n    a / (b + c)\n    -a / b\n")

      expect(muts.length).to eq(3)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "sets the operator name" do
      muts = mutations_for("    a / b\n")

      expect(muts.map(&:operator_name)).to eq(["integer_division_to_fdiv"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{receiver=local_variable_read{name=a}}"])

      muts = mutations_for("    a / b\n", filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
