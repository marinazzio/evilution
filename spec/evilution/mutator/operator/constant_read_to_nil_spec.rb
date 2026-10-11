# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ConstantReadToNil do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/constant_read_to_nil.rb", __dir__)
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
    it "replaces a bare constant with nil" do
      expect(mutated_lines(mutations_for("bare_constant"))).to eq(["nil"])
    end

    it "replaces a constant path as a whole" do
      expect(mutated_lines(mutations_for("constant_path"))).to eq(["nil"])
    end

    it "replaces a nested constant path once, not each of its segments" do
      expect(mutated_lines(mutations_for("nested_constant_path"))).to eq(["nil"])
    end

    it "replaces a top-level constant path" do
      expect(mutated_lines(mutations_for("top_level_path"))).to eq(["nil"])
    end

    it "replaces a constant in value position of an assignment" do
      expect(mutated_lines(mutations_for("assigned"))).to eq(["limit = nil"])
    end

    it "replaces a constant passed as an argument" do
      expect(mutated_lines(mutations_for("as_argument"))).to eq(["value.is_a?(nil)"])
    end

    it "replaces a constant used as an operand" do
      expect(mutated_lines(mutations_for("as_operand"))).to eq(["count == nil"])
    end

    it "replaces each constant of an expression in turn" do
      expect(mutated_lines(mutations_for("in_condition")))
        .to contain_exactly("count > nil ? MAX : count", "count > MAX ? nil : count")
    end

    it "replaces each constant of an array literal in turn" do
      expect(mutated_lines(mutations_for("in_array"))).to contain_exactly("[nil, SECOND]", "[FIRST, nil]")
    end

    it "replaces a constant matched by a when clause" do
      expect(mutated_lines(mutations_for("in_when"))).to eq(["when nil then 1"])
    end

    it "replaces a constant path hanging off an expression" do
      expect(mutated_lines(mutations_for("path_on_expression"))).to eq(["nil"])
    end

    it "still mutates a constant inside the expression a path hangs off" do
      expect(mutated_lines(mutations_for("path_on_call")))
        .to contain_exactly("nil", "resolve(nil, name)::LIMIT")
    end

    it "skips a constant that is the receiver of a call" do
      expect(mutations_for("call_receiver")).to be_empty
    end

    it "skips a constant path that is the receiver of a call" do
      expect(mutations_for("path_call_receiver")).to be_empty
    end

    it "skips the constant at the head of a call chain" do
      expect(mutations_for("chained_call_receiver")).to be_empty
    end

    it "skips a constant in void statement position, which statement_deletion covers" do
      expect(mutations_for("void_statement")).to be_empty
    end

    it "skips the exception classes of a rescue clause" do
      expect(mutations_for("rescue_class")).to be_empty
    end

    it "still mutates a constant in the body of a rescue clause" do
      expect(mutated_lines(mutations_for("rescue_body"))).to eq(["nil"])
    end

    it "emits nothing for a method without constants" do
      expect(mutations_for("no_constants")).to be_empty
    end

    it "reports the mutation on the line of the constant" do
      expect(mutations_for("bare_constant").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("bare_constant").map(&:operator_name).uniq).to eq(["constant_read_to_nil"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["constant_read"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#bare_constant") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
