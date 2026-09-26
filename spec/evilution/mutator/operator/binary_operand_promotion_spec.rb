# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BinaryOperandPromotion do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/binary_operand_promotion.rb", __dir__)
  end
  let(:source) { File.read(fixture_path) }
  let(:tree) { Prism.parse(source).value }

  def subjects_from_fixture
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(tree)
    finder.subjects
  end

  def mutations_for(method_name)
    subject = subjects_from_fixture.find { |s| s.name.end_with?("##{method_name}") }
    described_class.new.call(subject)
  end

  def mutations_from_source(inline_source)
    Tempfile.create(["binary_operand_promotion", ".rb"]) do |tmpfile|
      tmpfile.write(inline_source)
      tmpfile.flush
      Evilution::AST::Parser.new.call(tmpfile.path).flat_map { |s| described_class.new.call(s) }
    end
  end

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  describe "#call" do
    it "promotes each operand of an arithmetic operator" do
      expect(mutated_lines(mutations_for("add"))).to contain_exactly("a", "b")
    end

    it "promotes each operand of a bitwise operator" do
      expect(mutated_lines(mutations_for("bitwise"))).to contain_exactly("flags", "mask")
    end

    it "promotes each operand of a shift" do
      expect(mutated_lines(mutations_for("shift"))).to contain_exactly("value", "bits")
    end

    it "promotes call operands as written" do
      expect(mutated_lines(mutations_for("call_operands"))).to contain_exactly("order.subtotal", "order.tax_rate")
    end

    %w[- / % ** | ^ >>].each do |operator|
      it "promotes the operands of #{operator}" do
        muts = mutations_from_source("def t(a, b)\n  a #{operator} b\nend\n")

        expect(mutated_lines(muts)).to contain_exactly("a", "b")
      end
    end

    it "promotes operands of a nested expression at each level" do
      muts = mutations_from_source("def t(a, b, c)\n  a + b * c\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("a", "b * c", "a + b", "a + c")
    end

    it "promotes an operand inside a larger expression" do
      muts = mutations_from_source("def t(a, b)\n  total = a - b\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("total = a", "total = b")
    end

    it "keeps only the literal when the other operand is an additive identity" do
      expect(mutated_lines(mutations_for("plus_zero"))).to eq(["0"])
    end

    it "keeps only the literal when the identity is on the left" do
      expect(mutated_lines(mutations_for("zero_plus"))).to eq(["0"])
    end

    it "keeps only the literal when the other operand is a multiplicative identity" do
      expect(mutated_lines(mutations_for("times_one"))).to eq(["1"])
    end

    it "promotes both operands of 0 - b, which is -b rather than b" do
      muts = mutations_from_source("def t(b)\n  0 - b\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("0", "b")
    end

    it "promotes both operands of << 0, which may append" do
      muts = mutations_from_source("def t(list)\n  list << 0\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("list", "0")
    end

    it "treats a float zero as meaningful, since it changes the result type" do
      expect(mutated_lines(mutations_for("plus_float_zero"))).to contain_exactly("a", "0.0")
    end

    it "skips a binary send in void statement position" do
      expect(mutations_for("void_append")).to be_empty
    end

    it "skips comparisons" do
      expect(mutations_for("comparison")).to be_empty
    end

    it "skips an explicit operator call with more than one argument" do
      expect(mutations_from_source("def t(a, b, c)\n  a.+(b, c)\nend\n")).to be_empty
    end

    it "skips an explicit operator call without arguments" do
      expect(mutations_from_source("def t(a)\n  a.+()\nend\n")).to be_empty
    end

    it "skips a unary operator" do
      expect(mutations_from_source("def t(a)\n  -a\nend\n")).to be_empty
    end

    it "reports the mutation on the line of the expression" do
      expect(mutations_for("add").map(&:line)).to eq([3, 3])
    end

    it "names the operator" do
      expect(mutations_for("add").map(&:operator_name).uniq).to eq(["binary_operand_promotion"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#add") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(2)
    end
  end
end
