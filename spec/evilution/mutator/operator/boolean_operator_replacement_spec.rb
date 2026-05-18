# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BooleanOperatorReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/boolean_operator.rb", __dir__) }
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
    tmpfile = Tempfile.new(["boolean_operator", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "replaces && with ||" do
      muts = mutations_for("both_true?")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a || b")
    end

    it "replaces || with &&" do
      muts = mutations_for("either_true?")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a && b")
    end

    it "replaces 'and' with 'or'" do
      muts = mutations_for("word_and?")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a or b")
    end

    it "replaces 'or' with 'and'" do
      muts = mutations_for("word_or?")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a and b")
    end

    it "recurses into a nested && so the inner operator is also replaced" do
      muts = mutations_from_source("class C\n  def m(a, b, c)\n    a && b && c\n  end\nend\n")

      expect(muts.length).to eq(2)
    end

    it "recurses into a nested || so the inner operator is also replaced" do
      muts = mutations_from_source("class C\n  def m(a, b, c)\n    a || b || c\n  end\nend\n")

      expect(muts.length).to eq(2)
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          expect { Prism.parse(mutation.mutated_source) }.not_to raise_error,
                                                                 "Invalid Ruby produced for #{mutation}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("both_true?")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("boolean_operator_replacement")
      end
    end
  end
end
