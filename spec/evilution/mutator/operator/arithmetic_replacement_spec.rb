# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ArithmeticReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/arithmetic.rb", __dir__) }
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

  describe "#call" do
    it "replaces + with -" do
      muts = mutations_for("add")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a - b")
    end

    it "replaces - with +" do
      muts = mutations_for("subtract")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a + b")
    end

    it "replaces * with /" do
      muts = mutations_for("multiply")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a / b")
    end

    it "replaces / with *" do
      muts = mutations_for("divide")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a * b")
    end

    it "replaces % with *" do
      muts = mutations_for("modulo")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a * b")
    end

    it "replaces ** with *" do
      muts = mutations_for("power")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a * b")
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
      muts = mutations_for("add")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("arithmetic_replacement")
      end
    end

    it "does not mutate methods with no arithmetic operators" do
      # Build a subject from a source with no arithmetic
      plain_source = "class Foo\n  def greet\n    'hello'\n  end\nend"
      plain_path = fixture_path # reuse path for SubjectFinder, source is what matters
      tree = Prism.parse(plain_source).value
      finder = Evilution::AST::SubjectFinder.new(plain_source, plain_path)
      finder.visit(tree)
      subj = finder.subjects.find { |s| s.name.end_with?("#greet") }

      muts = described_class.new.call(subj)
      expect(muts).to be_empty
    end
  end
end
