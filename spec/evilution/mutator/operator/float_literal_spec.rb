# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::FloatLiteral do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/float_literal.rb", __dir__) }
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
    it "replaces 0.0 with 1.0 and nil" do
      muts = mutations_for("zero_float")

      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def zero_float\s+1\.0\s+end/),
        a_string_matching(/def zero_float\s+nil\s+end/)
      )
    end

    it "replaces 1.0 with 0.0 and nil" do
      muts = mutations_for("one_float")

      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def one_float\s+0\.0\s+end/),
        a_string_matching(/def one_float\s+nil\s+end/)
      )
    end

    it "replaces 3.14 with 0.0 and nil" do
      muts = mutations_for("pi_float")

      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def pi_float\s+0\.0\s+end/),
        a_string_matching(/def pi_float\s+nil\s+end/)
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
      muts = mutations_for("zero_float")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("float_literal")
      end
    end
  end
end
