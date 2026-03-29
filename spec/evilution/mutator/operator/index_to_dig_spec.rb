# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::IndexToDig do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/nested_index.rb", __dir__) }
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
    it "replaces h[:a][:b] with h.dig(:a, :b)" do
      muts = mutations_for("two_level")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("h.dig(:a, :b)")
    end

    it "replaces h[:a][:b][:c] with h.dig(:a, :b, :c)" do
      muts = mutations_for("three_level")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("h.dig(:a, :b, :c)")
    end

    it "handles mixed key types" do
      muts = mutations_for("mixed_keys")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('h.dig("users", 0, :name)')
    end

    it "does not mutate single-level [] access" do
      muts = mutations_for("single_level")

      expect(muts).to be_empty
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
      muts = mutations_for("two_level")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("index_to_dig")
      end
    end

    it "does not mutate methods without [] access" do
      muts = mutations_for("no_index")

      expect(muts).to be_empty
    end
  end
end
