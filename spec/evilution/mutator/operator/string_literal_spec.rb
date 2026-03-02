# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::StringLiteral do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/string_literal.rb", __dir__) }
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
    it 'replaces "hello" with ""' do
      muts = mutations_for("returns_hello")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to match(/def returns_hello\s+""\s+end/)
    end

    it 'replaces "" with "mutation"' do
      muts = mutations_for("returns_empty")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to match(/def returns_empty\s+"mutation"\s+end/)
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
      muts = mutations_for("returns_hello")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("string_literal")
      end
    end
  end
end
