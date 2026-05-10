# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::IndexToAt do
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
    # EV-pn5y / GH #1173: Hash has no #at method, so symbol/string keys
    # (the typical Hash-key shape) must NOT be rewritten — doing so produced
    # NoMethodError crashes during self-mutation of in_process.rb.
    it "skips symbol-keyed access (likely Hash, no #at method)" do
      muts = mutations_for("hash_access")

      expect(muts).to be_empty
    end

    it "skips string-keyed access (likely Hash, no #at method)" do
      muts = mutations_for("string_key_access")

      expect(muts).to be_empty
    end

    it "replaces array[0] with array.at(0)" do
      muts = mutations_for("array_access")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a.at(0)")
    end

    it "replaces hash[k] with hash.at(k) (variable key — could be array index)" do
      muts = mutations_for("variable_key_access")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("h.at(k)")
    end

    it "does not mutate multi-argument [] access" do
      muts = mutations_for("multi_arg_access")

      expect(muts).to be_empty
    end

    it "does not mutate methods without [] access" do
      muts = mutations_for("no_index_access")

      expect(muts).to be_empty
    end

    it "handles multi-byte source correctly" do
      mb_path = File.expand_path("../../../support/fixtures/index_access_multibyte.rb", __dir__)
      mb_source = File.read(mb_path)
      mb_tree = Prism.parse(mb_source).value
      finder = Evilution::AST::SubjectFinder.new(mb_source, mb_path)
      finder.visit(mb_tree)
      subj = finder.subjects.find { |s| s.name.end_with?("#multibyte_before_access") }
      muts = described_class.new.call(subj)

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("h.at(k)")
      result = Prism.parse(muts.first.mutated_source)
      expect(result.errors).to be_empty
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
      muts = mutations_for("array_access")

      expect(muts).not_to be_empty
      muts.each do |mutation|
        expect(mutation.operator_name).to eq("index_to_at")
      end
    end
  end
end
