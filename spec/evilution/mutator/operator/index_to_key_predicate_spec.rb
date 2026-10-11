# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::IndexToKeyPredicate do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/index_to_key_predicate.rb", __dir__)
  end
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

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  describe "#call" do
    it "replaces an index read by symbol key with key?" do
      expect(mutated_lines(mutations_for("symbol_key"))).to eq(["config.key?(:size)"])
    end

    it "replaces an index read by variable key with key?" do
      expect(mutated_lines(mutations_for("variable_key"))).to eq(["hash.key?(key)"])
    end

    it "replaces an index read by string key with key?" do
      expect(mutated_lines(mutations_for("string_key"))).to eq(['headers.key?("Accept")'])
    end

    it "keeps the whole receiver chain" do
      expect(mutated_lines(mutations_for("chained_receiver"))).to eq(["request.params.key?(key)"])
    end

    it "replaces an index read used as a condition" do
      expect(mutated_lines(mutations_for("in_condition"))).to eq(["config.key?(:verbose) ? 1 : 2"])
    end

    it "replaces an index read that is the receiver of another call" do
      expect(mutated_lines(mutations_for("compared"))).to eq(["config.key?(:mode) == expected"])
    end

    it "replaces an index read in value position of an assignment" do
      expect(mutated_lines(mutations_for("assigned"))).to eq(["value = hash.key?(key)"])
    end

    it "mutates each index read of a nested lookup" do
      expect(mutated_lines(mutations_for("nested_lookup")))
        .to contain_exactly("table[row].key?(column)", "table.key?(row)[column]")
    end

    it "keeps the safe navigation of the index read" do
      expect(mutated_lines(mutations_for("safe_navigation"))).to eq(["hash&.key?(key)"])
    end

    it "skips an index read in void statement position, whose value is discarded" do
      expect(mutations_for("void_statement")).to be_empty
    end

    it "skips an integer index, which points at an Array" do
      expect(mutations_for("integer_index")).to be_empty
    end

    it "skips a negative integer index" do
      expect(mutations_for("negative_index")).to be_empty
    end

    it "skips a range index, which points at an Array or a String" do
      expect(mutations_for("range_index")).to be_empty
    end

    it "skips an index read with several arguments" do
      expect(mutations_for("multiple_arguments")).to be_empty
    end

    it "skips an index read with a splat argument" do
      expect(mutations_for("splat_argument")).to be_empty
    end

    it "skips an index read without arguments" do
      expect(mutations_for("no_arguments")).to be_empty
    end

    it "skips an index write" do
      expect(mutations_for("index_write")).to be_empty
    end

    it "skips an index operator write" do
      expect(mutations_for("index_or_write")).to be_empty
    end

    it "skips a named method call" do
      expect(mutations_for("named_call")).to be_empty
    end

    it "reports the mutation on the line of the index read" do
      expect(mutations_for("symbol_key").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("symbol_key").map(&:operator_name).uniq).to eq(["index_to_key_predicate"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=[]}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#symbol_key") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
