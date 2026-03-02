# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::NilReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/nil_literal.rb", __dir__) }
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
    it "replaces nil with true" do
      muts = mutations_for("returns_nil")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to match(/def returns_nil\s+true\s+end/)
    end

    it "replaces nil with true in a method containing a nil literal" do
      muts = mutations_for("nil_with_logic")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to match(/return true if flag/)
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
      muts = mutations_for("returns_nil")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("nil_replacement")
      end
    end
  end
end
