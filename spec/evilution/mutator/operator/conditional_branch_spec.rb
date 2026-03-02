# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ConditionalBranch do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/conditional_branch.rb", __dir__) }
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
    it "generates 2 mutations for if/else (nil-ify each branch)" do
      muts = mutations_for("with_else")

      expect(muts.length).to eq(2)
    end

    it "nil-ifies the if-branch body for if/else" do
      muts = mutations_for("with_else")

      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(a_string_matching(/if x > 0\s+nil\s+else/))
    end

    it "nil-ifies the else-branch body for if/else" do
      muts = mutations_for("with_else")

      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(a_string_matching(/else\s+nil\s+end/))
    end

    it "generates 1 mutation for if without else (nil-ify the if-body)" do
      muts = mutations_for("without_else")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to match(/if x > 0\s+nil\s+end/)
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
      muts = mutations_for("with_else")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("conditional_branch")
      end
    end
  end
end
