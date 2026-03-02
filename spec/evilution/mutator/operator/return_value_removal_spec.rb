# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ReturnValueRemoval do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/return_value.rb", __dir__) }
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
    it "replaces return x + 1 with bare return" do
      muts = mutations_for("with_return_value")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to match(/def with_return_value\(x\)\s+return\s+end/)
    end

    it "generates 0 mutations for a bare return" do
      muts = mutations_for("bare_return")

      expect(muts.length).to eq(0)
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
      muts = mutations_for("with_return_value")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("return_value_removal")
      end
    end
  end
end
