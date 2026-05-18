# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::HashLiteral do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/hash_literal.rb", __dir__) }
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
    it "replaces { a: 1, b: 2 } with {} and nil" do
      muts = mutations_for("returns_populated_hash")

      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def returns_populated_hash\s+\{\}\s+end/),
        a_string_matching(/def returns_populated_hash\s+nil\s+end/)
      )
    end

    it "produces no mutations for an empty hash" do
      muts = mutations_for("returns_empty_hash")

      expect(muts).to be_empty
    end

    it "recurses into hash elements to mutate a nested hash literal" do
      # `{ a: { b: 1 } }`: the outer hash yields 2 mutations and the nested
      # `{ b: 1 }` hash yields 2 more — only reached when the visitor recurses
      # into the hash elements.
      muts = mutations_for("returns_nested_hash")

      expect(muts.length).to eq(4)
      expect(muts.any? { |m| m.mutated_source.include?("{ a: {} }") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("{ a: nil }") }).to be true
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
      muts = mutations_for("returns_populated_hash")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("hash_literal")
      end
    end
  end
end
