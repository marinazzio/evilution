# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BooleanLiteralReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/boolean_literal.rb", __dir__) }
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
    it "replaces true with false and nil" do
      muts = mutations_for("always_true")

      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def always_true\s+false\s+end/),
        a_string_matching(/def always_true\s+nil\s+end/)
      )
    end

    it "replaces false with true and nil" do
      muts = mutations_for("always_false")

      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def always_false\s+true\s+end/),
        a_string_matching(/def always_false\s+nil\s+end/)
      )
    end

    it "replaces all boolean literals in a method with multiple booleans" do
      muts = mutations_for("mixed_booleans")

      expect(muts.length).to eq(4)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/return false if flag/),
        a_string_matching(/return true if flag/)
      )
      expect(mutated_sources.count { |s| s.include?("nil") }).to eq(2)
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
      muts = mutations_for("always_true")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("boolean_literal_replacement")
      end
    end
  end
end
