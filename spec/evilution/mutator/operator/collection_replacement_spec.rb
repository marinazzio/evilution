# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::CollectionReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/collection.rb", __dir__) }
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
    it "replaces map with each" do
      muts = mutations_for("transform")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.each")
    end

    it "replaces each with map" do
      muts = mutations_for("iterate")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.map")
    end

    it "replaces select with reject" do
      muts = mutations_for("filter_in")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.reject")
    end

    it "replaces reject with select" do
      muts = mutations_for("filter_out")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.select")
    end

    it "replaces flat_map with map" do
      muts = mutations_for("flatten_transform")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.map")
    end

    it "replaces collect with each" do
      muts = mutations_for("collect_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.each")
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
      muts = mutations_for("transform")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("collection_replacement")
      end
    end

    it "does not mutate methods with no collection operators" do
      plain_source = "class Foo\n  def greet\n    'hello'\n  end\nend"
      tree = Prism.parse(plain_source).value
      finder = Evilution::AST::SubjectFinder.new(plain_source, fixture_path)
      finder.visit(tree)
      subj = finder.subjects.find { |s| s.name.end_with?("#greet") }

      muts = described_class.new.call(subj)
      expect(muts).to be_empty
    end
  end
end
