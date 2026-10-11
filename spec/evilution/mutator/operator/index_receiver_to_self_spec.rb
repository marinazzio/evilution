# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::IndexReceiverToSelf do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/index_receiver_to_self.rb", __dir__)
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
    it "replaces a local variable receiver with self" do
      expect(mutated_lines(mutations_for("local_receiver"))).to eq(["self[key]"])
    end

    it "replaces an implicit-self call receiver with self" do
      expect(mutated_lines(mutations_for("call_receiver"))).to eq(["self[key]"])
    end

    it "replaces a whole receiver chain with self" do
      expect(mutated_lines(mutations_for("chained_receiver"))).to eq(["self[key]"])
    end

    it "replaces an instance variable receiver with self" do
      expect(mutated_lines(mutations_for("instance_variable_receiver"))).to eq(["self[key]"])
    end

    it "keeps every index argument" do
      expect(mutated_lines(mutations_for("multiple_arguments"))).to eq(["self[1, 2]"])
    end

    it "mutates each index read of a nested lookup" do
      expect(mutated_lines(mutations_for("nested_index"))).to contain_exactly("self[column]", "self[row][column]")
    end

    it "replaces the receiver of an index read in value position of an assignment" do
      expect(mutated_lines(mutations_for("assigned"))).to eq(["value = self[key]"])
    end

    it "replaces the receiver of a safe-navigation index read" do
      expect(mutated_lines(mutations_for("safe_navigation"))).to eq(["self&.[](key)"])
    end

    it "skips an index read already sent to self" do
      expect(mutations_for("already_self")).to be_empty
    end

    it "skips an index write" do
      expect(mutations_for("index_write")).to be_empty
    end

    it "skips an index operator write" do
      expect(mutations_for("index_or_write")).to be_empty
    end

    it "skips an array literal" do
      expect(mutations_for("array_literal")).to be_empty
    end

    it "skips a named method call" do
      expect(mutations_for("named_call")).to be_empty
    end

    it "reports the mutation on the line of the index read" do
      expect(mutations_for("local_receiver").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("local_receiver").map(&:operator_name).uniq).to eq(["index_receiver_to_self"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=[]}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#local_receiver") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
