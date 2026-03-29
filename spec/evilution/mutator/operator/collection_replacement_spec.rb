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

    it "replaces sort with sort_by" do
      muts = mutations_for("sort_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.sort_by")
    end

    it "replaces sort_by with sort" do
      muts = mutations_for("sort_by_items")

      sort_mut = muts.find { |m| m.mutated_source.include?("items.sort {") }
      expect(sort_mut).not_to be_nil
    end

    it "also replaces length inside sort_by block" do
      muts = mutations_for("sort_by_items")

      count_mut = muts.find { |m| m.mutated_source.include?("i.count") }
      expect(count_mut).not_to be_nil
    end

    it "replaces find with detect" do
      muts = mutations_for("find_item")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.detect")
    end

    it "replaces detect with find" do
      muts = mutations_for("detect_item")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.find")
    end

    it "replaces any? with all?" do
      muts = mutations_for("check_any")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.all?")
    end

    it "replaces all? with any?" do
      muts = mutations_for("check_all")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.any?")
    end

    it "replaces count with length" do
      muts = mutations_for("count_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.length")
    end

    it "replaces length with count" do
      muts = mutations_for("length_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.count")
    end

    it "replaces pop with shift" do
      muts = mutations_for("pop_item")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.shift")
    end

    it "replaces shift with pop" do
      muts = mutations_for("shift_item")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.pop")
    end

    it "replaces push with unshift" do
      muts = mutations_for("push_item")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.unshift")
    end

    it "replaces unshift with push" do
      muts = mutations_for("unshift_item")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.push")
    end

    it "replaces each_key with each_value" do
      muts = mutations_for("iterate_keys")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("hash.each_value")
    end

    it "replaces each_value with each_key" do
      muts = mutations_for("iterate_values")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("hash.each_key")
    end

    it "replaces assoc with rassoc" do
      muts = mutations_for("assoc_lookup")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("hash.rassoc")
    end

    it "replaces rassoc with assoc" do
      muts = mutations_for("rassoc_lookup")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("hash.assoc")
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
