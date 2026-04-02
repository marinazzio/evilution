# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::CollectionReturn do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/collection_return.rb", __dir__) }
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
    it "replaces non-empty array return with []" do
      muts = mutations_for("returns_array")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to match(/def returns_array\s+\[\]\s+end/)
    end

    it "replaces non-empty hash return with {}" do
      muts = mutations_for("returns_hash")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to match(/def returns_hash\s+\{\}\s+end/)
    end

    it "does not mutate empty array return" do
      muts = mutations_for("returns_empty_array")

      expect(muts).to be_empty
    end

    it "does not mutate empty hash return" do
      muts = mutations_for("returns_empty_hash")

      expect(muts).to be_empty
    end

    it "does not mutate non-collection returns" do
      expect(mutations_for("returns_string")).to be_empty
      expect(mutations_for("returns_nil")).to be_empty
      expect(mutations_for("returns_integer")).to be_empty
    end

    it "does not mutate empty methods" do
      muts = mutations_for("empty_method")

      expect(muts).to be_empty
    end

    it "replaces body with [] when last expression is array" do
      muts = mutations_for("multi_line_returns_array")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to match(/def multi_line_returns_array\s+\[\]\s+end/)
    end

    it "replaces body with {} when last expression is hash" do
      muts = mutations_for("multi_line_returns_hash")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to match(/def multi_line_returns_hash\s+\{\}\s+end/)
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
      muts = mutations_for("returns_array")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("collection_return")
      end
    end
  end
end
