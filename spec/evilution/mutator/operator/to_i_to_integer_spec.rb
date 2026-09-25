# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ToIToInteger do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/to_i_to_integer.rb", __dir__)
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
    tmpfile = Tempfile.new(["to_i_to_integer", ".rb"])
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
    it "rewrites x.to_i to Integer(x)" do
      expect(mutated_lines(mutations_for("plain"))).to eq(["Integer(value)"])
    end

    it "carries a base argument into Integer()" do
      expect(mutated_lines(mutations_for("with_base"))).to eq(["Integer(value, 16)"])
    end

    it "keeps a compound receiver intact" do
      expect(mutated_lines(mutations_for("compound_receiver"))).to eq(["Integer(params[:page])"])
    end

    it "rewrites a safe-navigation call" do
      expect(mutated_lines(mutations_for("safe_navigation"))).to eq(["Integer(value)"])
    end

    it "rewrites a call nested in another call" do
      muts = mutations_from_source("def t(v)\n  page(v.to_i)\nend\n")

      expect(mutated_lines(muts)).to eq(["page(Integer(v))"])
    end

    it "keeps an operator receiver as a whole" do
      muts = mutations_from_source("def t(a, b)\n  (a + b).to_i\nend\n")

      expect(mutated_lines(muts)).to eq(["Integer((a + b))"])
    end

    it "skips an integer literal receiver, where both agree" do
      expect(mutations_for("integer_literal")).to be_empty
    end

    it "skips a float literal receiver, where both agree" do
      expect(mutations_for("float_literal")).to be_empty
    end

    it "skips a receiverless call" do
      expect(mutations_for("receiverless")).to be_empty
    end

    it "skips other conversions" do
      expect(mutations_for("other_method")).to be_empty
    end

    it "skips more than one argument" do
      expect(mutations_from_source("def t(v)\n  v.to_i(16, 2)\nend\n")).to be_empty
    end

    it "skips a splat argument" do
      expect(mutations_from_source("def t(v, args)\n  v.to_i(*args)\nend\n")).to be_empty
    end

    it "skips a call with a block" do
      expect(mutations_from_source("def t(v)\n  v.to_i { 1 }\nend\n")).to be_empty
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("plain").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("plain").map(&:operator_name).uniq).to eq(["to_i_to_integer"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=to_i}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#plain") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
