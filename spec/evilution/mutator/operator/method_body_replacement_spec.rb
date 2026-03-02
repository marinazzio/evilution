# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::MethodBodyReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/method_body.rb", __dir__) }
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
    it "generates 1 mutation for a method with a body" do
      muts = mutations_for("with_body")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to match(/def with_body\s+nil\s+end/)
    end

    it "generates 0 mutations for an empty method" do
      muts = mutations_for("empty_method")

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
      muts = mutations_for("with_body")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("method_body_replacement")
      end
    end
  end
end
