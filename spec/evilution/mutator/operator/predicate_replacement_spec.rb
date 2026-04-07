# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::PredicateReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/predicate_replacement.rb", __dir__) }
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
    it "replaces predicate with true and false" do
      muts = mutations_for("simple_predicate")

      expect(muts.length).to eq(2)
      expect(muts.map(&:mutated_source)).to include(
        a_string_including("true"),
        a_string_including("false")
      )
    end

    it "replaces predicate with receiver and args" do
      muts = mutations_for("predicate_with_receiver")

      expect(muts.length).to eq(2)
      replacements = muts.map { |m| m.diff.lines.select { |l| l.start_with?("+") }.join }
      expect(replacements).to include(a_string_including("true"), a_string_including("false"))
    end

    it "replaces bare predicate" do
      muts = mutations_for("bare_predicate")

      expect(muts.length).to eq(2)
    end

    it "replaces nil? check" do
      muts = mutations_for("nil_check")

      expect(muts.length).to eq(2)
    end

    it "replaces predicate with block" do
      muts = mutations_for("predicate_with_block")

      expect(muts.length).to eq(2)
    end

    it "skips non-predicate methods" do
      muts = mutations_for("non_predicate_method")

      expect(muts).to be_empty
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty,
                                   "Invalid Ruby produced for #{mutation}: #{result.errors.map(&:message)}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("simple_predicate")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("predicate_replacement")
      end
    end
  end
end
