# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::IndexToFetch do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/index_access.rb", __dir__) }
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
    it "replaces hash[:key] with hash.fetch(:key)" do
      muts = mutations_for("hash_access")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("h.fetch(:key)")
    end

    it "replaces array[0] with array.fetch(0)" do
      muts = mutations_for("array_access")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a.fetch(0)")
    end

    it "replaces hash[\"name\"] with hash.fetch(\"name\")" do
      muts = mutations_for("string_key_access")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('h.fetch("name")')
    end

    it "replaces hash[k] with hash.fetch(k)" do
      muts = mutations_for("variable_key_access")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("h.fetch(k)")
    end

    it "does not mutate multi-argument [] access" do
      muts = mutations_for("multi_arg_access")

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
      muts = mutations_for("hash_access")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("index_to_fetch")
      end
    end

    it "does not mutate methods without [] access" do
      muts = mutations_for("no_index_access")

      expect(muts).to be_empty
    end
  end
end
