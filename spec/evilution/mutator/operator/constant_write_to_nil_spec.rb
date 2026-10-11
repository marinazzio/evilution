# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ConstantWriteToNil do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/constant_write_to_nil.rb", __dir__)
  end
  let(:subjects) { Evilution::AST::Parser.new.call(fixture_path) }

  def subject_named(name)
    subjects.find { |s| s.name == name }
  end

  def mutations_for(name)
    described_class.new.call(subject_named(name))
  end

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  it "mutates constant-write subjects only" do
    expect(described_class.subject_kinds).to eq(%i[constant_write])
  end

  describe "#call" do
    it "replaces a literal value with nil" do
      expect(mutated_lines(mutations_for("ConstantWriteToNilTarget::LIMIT"))).to eq(["LIMIT = nil"])
    end

    it "replaces a value with a trailing call whole" do
      expect(mutated_lines(mutations_for("ConstantWriteToNilTarget::NAME"))).to eq(["NAME = nil"])
    end

    it "replaces a value written over several lines whole" do
      muts = mutations_for("ConstantWriteToNilTarget::DEFAULTS")

      expect(mutated_lines(muts)).to eq(["DEFAULTS = nil"])
      expect(muts.first.mutated_source).to include("  DEFAULTS = nil\n  HANDLER")
    end

    it "replaces a lambda value with nil" do
      expect(mutated_lines(mutations_for("ConstantWriteToNilTarget::HANDLER"))).to eq(["HANDLER = nil"])
    end

    it "replaces a computed value with nil" do
      expect(mutated_lines(mutations_for("ConstantWriteToNilTarget::COMPUTED"))).to eq(["COMPUTED = nil"])
    end

    it "replaces a heredoc value, body included" do
      muts = mutations_for("ConstantWriteToNilTarget::QUERY")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("  QUERY = nil\n  Builder")
      expect(muts.first.mutated_source).not_to include("SELECT 1")
    end

    it "replaces the value of a constant path assignment" do
      expect(mutated_lines(mutations_for("ConstantWriteToNilTarget::EXTRA")))
        .to eq(["ConstantWriteToNilTarget::EXTRA = nil"])
    end

    it "replaces a class built in the value once, leaving constants inside it to their own subjects" do
      muts = mutations_for("ConstantWriteToNilTarget::Builder")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("  Builder = nil\n  Point")
      expect(mutated_lines(mutations_for("ConstantWriteToNilTarget::INNER"))).to eq(["INNER = nil"])
    end

    it "skips a constant already assigned nil" do
      expect(mutations_for("ConstantWriteToNilTarget::UNSET")).to be_empty
    end

    it "reports the mutation on the line of the assignment" do
      expect(mutations_for("ConstantWriteToNilTarget::DEFAULTS").map(&:line)).to eq([4])
    end

    it "names the operator" do
      expect(mutations_for("ConstantWriteToNilTarget::LIMIT").map(&:operator_name)).to eq(["constant_write_to_nil"])
    end

    it "produces parseable mutations" do
      muts = subjects.select { |s| s.kind == :constant_write }.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["constant_write"])

      muts = described_class.new.call(subject_named("ConstantWriteToNilTarget::LIMIT"), filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
