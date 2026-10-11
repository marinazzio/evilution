# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::OperatorWriteReceiverPromotion do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/operator_write_receiver_promotion.rb", __dir__)
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
    it "retargets an operator write at the instance variable it goes through" do
      expect(mutated_lines(mutations_for("add_assign"))).to eq(["@account += amount"])
    end

    it "mutates a write that is one of several statements" do
      expect(mutated_lines(mutations_for("subtract_assign"))).to eq(["@stock -= 1"])
    end

    it "keeps the operator of the write" do
      expect(mutated_lines(mutations_for("shift_assign"))).to eq(["@queue <<= item"])
    end

    it "drops the safe navigation along with the attribute" do
      expect(mutated_lines(mutations_for("safe_navigation"))).to eq(["@account += amount"])
    end

    it "keeps an expression value whole" do
      expect(mutated_lines(mutations_for("expression_value"))).to eq(["@totals += first * second"])
    end

    it "mutates a write inside a block" do
      expect(mutated_lines(mutations_for("in_block"))).to eq(["amounts.each { |amount| @account += amount }"])
    end

    it "mutates a write nested in the value of another" do
      expect(mutated_lines(mutations_for("nested_write")))
        .to contain_exactly("@account += (@stock.count -= 1)", "@account.balance += (@stock -= 1)")
    end

    it "skips a write through a local variable" do
      expect(mutations_for("local_receiver")).to be_empty
    end

    it "skips a write on self, which cannot be assigned" do
      expect(mutations_for("self_receiver")).to be_empty
    end

    it "skips a write whose receiver is a call on the instance variable" do
      expect(mutations_for("chained_receiver")).to be_empty
    end

    it "skips a write through a class variable" do
      expect(mutations_for("class_variable_receiver")).to be_empty
    end

    it "skips a logical write" do
      expect(mutations_for("logical_write")).to be_empty
    end

    it "skips an index operator write" do
      expect(mutations_for("index_write")).to be_empty
    end

    it "skips a plain attribute write" do
      expect(mutations_for("plain_write")).to be_empty
    end

    it "skips an operator write on the variable itself" do
      expect(mutations_for("variable_write")).to be_empty
    end

    it "reports the mutation on the line of the write" do
      expect(mutations_for("subtract_assign").map(&:line)).to eq([7])
    end

    it "names the operator" do
      expect(mutations_for("add_assign").map(&:operator_name)).to eq(["operator_write_receiver_promotion"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call_operator_write"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#add_assign") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
