# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::IndexWriteToValue do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/index_write_to_value.rb", __dir__)
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
    it "replaces an index write with the assigned value" do
      expect(mutated_lines(mutations_for("sole_statement"))).to eq(["value"])
    end

    it "mutates a write that is the last statement of a body, whose value is returned" do
      muts = mutations_for("last_statement")

      expect(mutated_lines(muts)).to eq(["value"])
      expect(muts.map(&:line)).to eq([8])
    end

    it "keeps an expression value whole" do
      expect(mutated_lines(mutations_for("expression_value"))).to eq(["step + 1"])
    end

    it "keeps a call value whole" do
      expect(mutated_lines(mutations_for("call_value"))).to eq(["compute(key)"])
    end

    it "promotes the value of a write with several indexes, not an index" do
      expect(mutated_lines(mutations_for("multiple_indexes"))).to eq(["value"])
    end

    it "drops the whole receiver chain" do
      expect(mutated_lines(mutations_for("chained_receiver"))).to eq(["value"])
    end

    it "mutates a write guarded by a modifier" do
      expect(mutated_lines(mutations_for("guarded"))).to eq(["value if value"])
    end

    it "mutates a write inside a block body" do
      expect(mutated_lines(mutations_for("in_block"))).to eq(["keys.each { |key| 1 }"])
    end

    it "mutates a write in value position" do
      expect(mutated_lines(mutations_for("in_value_position"))).to eq(["stored = (value)"])
    end

    it "mutates the explicit method-call spelling" do
      expect(mutated_lines(mutations_for("explicit_call"))).to eq(["value"])
    end

    it "mutates a safe-navigation write" do
      expect(mutated_lines(mutations_for("safe_navigation"))).to eq(["value"])
    end

    it "skips a write in void statement position, where the value is discarded" do
      expect(mutations_for("void_statement")).to be_empty
    end

    it "skips a value that does not stand on its own" do
      expect(mutations_for("list_value")).to be_empty
    end

    it "skips an index operator write" do
      expect(mutations_for("operator_write")).to be_empty
    end

    it "skips a compound index write" do
      expect(mutations_for("compound_write")).to be_empty
    end

    it "skips an index target of a multiple assignment" do
      expect(mutations_for("multiple_assignment")).to be_empty
    end

    it "skips an attribute write" do
      expect(mutations_for("attribute_write")).to be_empty
    end

    it "skips an index read" do
      expect(mutations_for("index_read")).to be_empty
    end

    it "reports the mutation on the line of the index write" do
      expect(mutations_for("sole_statement").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("sole_statement").map(&:operator_name).uniq).to eq(["index_write_to_value"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=[]=}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#sole_statement") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
