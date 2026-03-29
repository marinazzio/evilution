# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::IndexAssignmentRemoval do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/index_assignment.rb", __dir__) }
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
    it "removes hash []= assignment" do
      muts = mutations_for("hash_assign")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).not_to include('h[:key] = "value"')
      expect(muts.first.mutated_source).to include("nil")
    end

    it "removes array []= assignment" do
      muts = mutations_for("array_assign")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).not_to include("a[0] = 42")
      expect(muts.first.mutated_source).to include("nil")
    end

    it "generates one mutation per []= statement" do
      muts = mutations_for("nested_assign")

      expect(muts.length).to eq(2)
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty, "Invalid Ruby produced for #{mutation}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("hash_assign")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("index_assignment_removal")
      end
    end

    it "does not mutate methods without []= access" do
      muts = mutations_for("no_assignment")

      expect(muts).to be_empty
    end
  end
end
