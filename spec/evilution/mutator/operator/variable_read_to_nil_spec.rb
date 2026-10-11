# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::VariableReadToNil do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/variable_read_to_nil.rb", __dir__)
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
    it "replaces a local variable read with nil" do
      expect(mutated_lines(mutations_for("local_variable"))).to eq(["nil"])
    end

    it "replaces an instance variable read with nil" do
      expect(mutated_lines(mutations_for("instance_variable"))).to eq(["nil"])
    end

    it "replaces a class variable read with nil" do
      expect(mutated_lines(mutations_for("class_variable"))).to eq(["nil"])
    end

    it "replaces a global variable read with nil" do
      expect(mutated_lines(mutations_for("global_variable"))).to eq(["nil"])
    end

    it "replaces self with nil" do
      expect(mutated_lines(mutations_for("self_reference"))).to eq(["nil"])
    end

    it "replaces a read in value position of an assignment, leaving the receiver read alone" do
      expect(mutated_lines(mutations_for("assigned"))).to eq(["copy = nil"])
    end

    it "replaces a read passed as a keyword argument" do
      expect(mutated_lines(mutations_for("keyword_argument"))).to eq(["build(name: nil)"])
    end

    it "replaces each read of an array literal in turn" do
      expect(mutated_lines(mutations_for("array_elements"))).to contain_exactly("[nil, second]", "[first, nil]")
    end

    it "replaces a read used as a hash value" do
      expect(mutated_lines(mutations_for("hash_value"))).to eq(["{ key: nil }"])
    end

    it "replaces the right operand of a boolean expression" do
      expect(mutated_lines(mutations_for("right_operand"))).to eq(["left && nil"])
    end

    it "replaces the subject of a case expression" do
      expect(mutated_lines(mutations_for("case_subject"))).to eq(["case nil"])
    end

    it "replaces a read of a block parameter" do
      expect(mutated_lines(mutations_for("block_local"))).to eq(["items.map { |item| nil }"])
    end

    it "replaces a splatted read" do
      expect(mutated_lines(mutations_for("splat"))).to eq(["build(*nil)"])
    end

    it "skips a read that is the receiver of a call" do
      expect(mutations_for("call_receiver")).to be_empty
    end

    it "skips self as the receiver of a call" do
      expect(mutations_for("self_receiver")).to be_empty
    end

    it "skips the read at the head of a call chain" do
      expect(mutations_for("chained_receiver")).to be_empty
    end

    it "skips a read in void statement position, which statement_deletion covers" do
      expect(mutations_for("void_statement")).to be_empty
    end

    it "skips the condition of a ternary, which conditional_negation covers, but not its branches" do
      expect(mutated_lines(mutations_for("condition"))).to contain_exactly("flag ? nil : no", "flag ? yes : nil")
    end

    it "skips the condition of a modifier if but not its body" do
      expect(mutated_lines(mutations_for("modifier_condition"))).to eq(["nil if flag"])
    end

    it "skips the condition of an unless but not its body" do
      expect(mutated_lines(mutations_for("unless_condition"))).to eq(["nil unless flag"])
    end

    it "skips the condition of a while loop but not its body" do
      expect(mutated_lines(mutations_for("loop_condition"))).to eq(["total = nil while flag"])
    end

    it "skips the condition of an until loop but not its body" do
      expect(mutated_lines(mutations_for("until_condition"))).to eq(["total = nil until flag"])
    end

    it "skips the left operand of &&, which the boolean operators cover" do
      expect(mutated_lines(mutations_for("and_operands"))).to eq(["left && nil"])
    end

    it "skips the left operand of ||" do
      expect(mutated_lines(mutations_for("or_operands"))).to eq(["left || nil"])
    end

    it "skips a block-pass argument, which block_pass_removal covers, but not the arguments beside it" do
      expect(mutated_lines(mutations_for("block_pass"))).to eq(["items.first(nil, &callable)"])
    end

    it "skips a double-splatted read but not the arguments beside it" do
      expect(mutated_lines(mutations_for("double_splat"))).to eq(["build(nil, **options)"])
    end

    it "still mutates reads inside a block-pass expression" do
      expect(mutated_lines(mutations_for("block_pass_expression"))).to eq(["items.each(&handlers[nil])"])
    end

    it "still mutates reads inside a double-splatted expression" do
      expect(mutated_lines(mutations_for("double_splat_expression"))).to eq(["build(**defaults.merge(nil))"])
    end

    it "skips the implicit value of a shorthand hash" do
      expect(mutations_for("shorthand_hash")).to be_empty
    end

    it "skips variable writes" do
      expect(mutations_for("writes_only")).to be_empty
    end

    it "emits nothing for a method without variables" do
      expect(mutations_for("no_variables")).to be_empty
    end

    it "reports the mutation on the line of the read" do
      expect(mutations_for("assigned").map(&:line)).to eq([23])
    end

    it "names the operator" do
      expect(mutations_for("local_variable").map(&:operator_name).uniq).to eq(["variable_read_to_nil"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["local_variable_read"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#local_variable") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
