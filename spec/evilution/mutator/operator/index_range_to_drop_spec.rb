# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::IndexRangeToDrop do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/index_range_to_drop.rb", __dir__)
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
    it "replaces a to-the-end range index from a literal start with drop" do
      expect(mutated_lines(mutations_for("literal_start"))).to eq(["list.drop(1)"])
    end

    it "replaces a to-the-end range index from a variable start with drop" do
      expect(mutated_lines(mutations_for("variable_start"))).to eq(["list.drop(offset)"])
    end

    it "keeps an expression start whole" do
      expect(mutated_lines(mutations_for("expression_start"))).to eq(["list.drop(index + 1)"])
    end

    it "replaces an endless range index with drop" do
      expect(mutated_lines(mutations_for("endless"))).to eq(["list.drop(offset)"])
    end

    it "replaces an endless range index written with three dots" do
      expect(mutated_lines(mutations_for("endless_exclusive"))).to eq(["list.drop(offset)"])
    end

    it "keeps the whole receiver chain" do
      expect(mutated_lines(mutations_for("chained_receiver"))).to eq(["report.rows.drop(offset)"])
    end

    it "replaces a range index in value position of an assignment" do
      expect(mutated_lines(mutations_for("assigned"))).to eq(["rest = list.drop(offset)"])
    end

    it "replaces a range index that is the receiver of another call" do
      expect(mutated_lines(mutations_for("receiver_of_call"))).to eq(["list.drop(offset).first"])
    end

    it "keeps the safe navigation of the index read" do
      expect(mutated_lines(mutations_for("safe_navigation"))).to eq(["list&.drop(offset)"])
    end

    it "skips a range index in void statement position, whose value is discarded" do
      expect(mutations_for("void_statement")).to be_empty
    end

    it "skips a start of zero, which is never out of range" do
      expect(mutations_for("zero_start")).to be_empty
    end

    it "skips a negative literal start, which drop rejects" do
      expect(mutations_for("negative_start")).to be_empty
    end

    it "skips a beginless range" do
      expect(mutations_for("beginless")).to be_empty
    end

    it "skips a range that excludes the last element" do
      expect(mutations_for("exclusive_end")).to be_empty
    end

    it "skips a range ending before the last element" do
      expect(mutations_for("other_end")).to be_empty
    end

    it "skips a range ending at a variable" do
      expect(mutations_for("variable_end")).to be_empty
    end

    it "skips a start-and-length index" do
      expect(mutations_for("start_and_length")).to be_empty
    end

    it "skips a range index followed by another argument" do
      expect(mutations_for("range_and_argument")).to be_empty
    end

    it "skips a plain index" do
      expect(mutations_for("plain_index")).to be_empty
    end

    it "skips an index write" do
      expect(mutations_for("index_write")).to be_empty
    end

    it "skips a named method call" do
      expect(mutations_for("named_call")).to be_empty
    end

    it "reports the mutation on the line of the index read" do
      expect(mutations_for("literal_start").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("literal_start").map(&:operator_name).uniq).to eq(["index_range_to_drop"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=[]}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#literal_start") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
