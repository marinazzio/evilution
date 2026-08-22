# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BooleanOperandPromotion do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/boolean_operand_promotion.rb", __dir__)
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
    tmpfile = Tempfile.new(["boolean_operand_promotion", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "promotes each operand of &&" do
      muts = mutations_for("both_true?")

      expect(muts.map { |m| m.mutated_slice.strip }).to contain_exactly("a", "b")
    end

    it "promotes each operand of ||" do
      muts = mutations_for("either_true?")

      expect(muts.map { |m| m.mutated_slice.strip }).to contain_exactly("a", "b")
    end

    it "promotes operands of the keyword `and` form" do
      muts = mutations_for("word_and?")

      expect(muts.map { |m| m.mutated_slice.strip }).to contain_exactly("a", "b")
    end

    it "promotes at every level of a chained expression" do
      muts = mutations_for("chained?")

      expect(muts.map { |m| m.mutated_slice.strip }).to contain_exactly(
        "a && b", "c", "a && c", "b && c"
      )
    end

    it "descends into a chained || expression" do
      muts = mutations_for("or_chained?")

      expect(muts.map { |m| m.mutated_slice.strip }).to contain_exactly(
        "a || b", "c", "a || c", "b || c"
      )
    end

    it "copies the operand source verbatim, including its own parentheses" do
      muts = mutations_for("parenthesised?")

      expect(muts.map { |m| m.mutated_slice.strip }).to contain_exactly("a", "(b + c)")
    end

    it "reports the mutation on the line of the boolean expression" do
      muts = mutations_for("both_true?")

      expect(muts.map(&:line).uniq).to eq([3])
    end

    it "names the operator" do
      muts = mutations_for("both_true?")

      expect(muts.map(&:operator_name).uniq).to eq(["boolean_operand_promotion"])
    end

    it "produces parseable mutations" do
      muts = mutations_for("chained?")

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "emits nothing for a method without boolean operators" do
      muts = mutations_from_source("def plain(a, b)\n  a + b\nend\n")

      expect(muts).to be_empty
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["and"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#both_true?") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(2)
    end
  end
end
