# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::SymbolLiteral do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/symbol_literal.rb", __dir__) }
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
    it "replaces :foo with :__evilution_mutated__ and nil" do
      muts = mutations_for("returns_foo")

      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def returns_foo\s+:__evilution_mutated__\s+end/),
        a_string_matching(/def returns_foo\s+nil\s+end/)
      )
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
      muts = mutations_for("returns_foo")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("symbol_literal")
      end
    end
  end
end
