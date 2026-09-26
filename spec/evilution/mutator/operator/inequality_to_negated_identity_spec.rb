# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::InequalityToNegatedIdentity do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/inequality_to_negated_identity.rb", __dir__)
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
    Tempfile.create(["inequality_to_negated_identity", ".rb"]) do |tmpfile|
      tmpfile.write(inline_source)
      tmpfile.flush
      Evilution::AST::Parser.new.call(tmpfile.path).flat_map { |s| described_class.new.call(s) }
    end
  end

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  describe "#call" do
    it "rewrites != to negated eql? and negated equal?" do
      expect(mutated_lines(mutations_for("plain"))).to contain_exactly("!a.eql?(b)", "!a.equal?(b)")
    end

    it "keeps method-call operands unwrapped" do
      expect(mutated_lines(mutations_for("call_operands")))
        .to contain_exactly("!user.id.eql?(other.id)", "!user.id.equal?(other.id)")
    end

    it "wraps a compound left operand in parentheses" do
      expect(mutated_lines(mutations_for("compound_left")))
        .to contain_exactly("!(a + b).eql?(c)", "!(a + b).equal?(c)")
    end

    it "keeps a compound right operand as the argument" do
      expect(mutated_lines(mutations_for("compound_right")))
        .to contain_exactly("!a.eql?(b + c)", "!a.equal?(b + c)")
    end

    it "wraps a negated left operand" do
      muts = mutations_from_source("def t(a, b)\n  !a != b\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("!(!a).eql?(b)", "!(!a).equal?(b)")
    end

    it "keeps a literal left operand unwrapped" do
      muts = mutations_from_source("def t(b)\n  \"a\" != b\nend\n")

      expect(mutated_lines(muts)).to contain_exactly('!"a".eql?(b)', '!"a".equal?(b)')
    end

    it "rewrites an inequality inside a condition" do
      muts = mutations_from_source("def t(a, b)\n  return 1 if a != b\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("return 1 if !a.eql?(b)", "return 1 if !a.equal?(b)")
    end

    it "keeps an index operand unwrapped" do
      muts = mutations_from_source("def t(x, y)\n  x[0] != y\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("!x[0].eql?(y)", "!x[0].equal?(y)")
    end

    it "wraps an interpolated-string operand" do
      muts = mutations_from_source("def t(a, b)\n  \"x\#{a}\" != b\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("!(\"x\#{a}\").eql?(b)", "!(\"x\#{a}\").equal?(b)")
    end

    it "rewrites an inequality nested in a block" do
      muts = mutations_from_source("def t(xs, y)\n  xs.select { |v| v != y }\nend\n")

      expect(mutated_lines(muts)).to contain_exactly(
        "xs.select { |v| !v.eql?(y) }", "xs.select { |v| !v.equal?(y) }"
      )
    end

    it "skips an explicit != call with more than one argument" do
      expect(mutations_from_source("def t(a, b, c)\n  a.!=(b, c)\nend\n")).to be_empty
    end

    it "skips a comparison against nil, where all forms agree" do
      expect(mutations_for("against_nil")).to be_empty
    end

    it "skips nil on the left" do
      expect(mutations_for("nil_on_the_left")).to be_empty
    end

    it "skips a comparison against a symbol literal" do
      expect(mutations_for("against_symbol")).to be_empty
    end

    it "skips a comparison against a boolean literal" do
      expect(mutations_for("against_boolean")).to be_empty
      expect(mutations_from_source("def t(f)\n  f != false\nend\n")).to be_empty
    end

    it "skips ==" do
      expect(mutations_for("equality")).to be_empty
    end

    it "reports the mutation on the line of the comparison" do
      expect(mutations_for("plain").map(&:line)).to eq([3, 3])
    end

    it "names the operator" do
      expect(mutations_for("plain").map(&:operator_name).uniq).to eq(["inequality_to_negated_identity"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#plain") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(2)
    end
  end
end
