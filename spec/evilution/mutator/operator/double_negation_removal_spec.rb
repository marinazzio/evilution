# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::DoubleNegationRemoval do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/double_negation_removal.rb", __dir__)
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
    tmpfile = Tempfile.new(["double_negation_removal", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  describe "#call" do
    it "replaces a double negation with its operand" do
      expect(mutated_lines(mutations_for("coerce"))).to eq(["value"])
    end

    it "keeps a call operand intact" do
      expect(mutated_lines(mutations_for("coerce_call"))).to eq(["user.admin"])
    end

    it "keeps a parenthesised operand's parentheses" do
      expect(mutated_lines(mutations_for("coerce_group"))).to eq(["(a && b)"])
    end

    it "handles the keyword form" do
      expect(mutated_lines(mutations_for("keyword_form"))).to eq(["value"])
    end

    it "mutates a double negation inside a condition" do
      expect(mutated_lines(mutations_for("in_condition"))).to eq(["return 1 if value"])
    end

    it "emits once per pair in a triple negation, keeping the other negation" do
      muts = mutations_from_source("def t(v)\n  !!!v\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("!v", "!v")
    end

    it "skips a single negation" do
      expect(mutations_for("single_negation")).to be_empty
    end

    it "skips a non-negation call whose receiver is a negation" do
      expect(mutations_from_source("def t(a, b)\n  !a == b\nend\n")).to be_empty
    end

    it "skips a negation of a parenthesised negation" do
      expect(mutations_from_source("def t(v)\n  !(!v)\nend\n")).to be_empty
    end

    it "reports the mutation on the line of the double negation" do
      expect(mutations_for("coerce").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("coerce").map(&:operator_name).uniq).to eq(["double_negation_removal"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#coerce") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
