# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::PinOperatorRemoval do
  def mutations_for(body, filter: nil)
    tmpfile = Tempfile.new(["pin_operator_removal", ".rb"])
    tmpfile.write("class Matcher\n  def call(value, a, b)\n#{body}  end\nend\n")
    tmpfile.flush
    subject = Evilution::AST::Parser.new.call(tmpfile.path).first
    described_class.new.call(subject, filter: filter)
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  # The line each mutation rewrote.
  def mutated_lines(muts)
    muts.map { |m| m.mutated_source.lines[m.line - 1].strip }
  end

  describe "#call" do
    it "drops the pin of a case/in pattern" do
      muts = mutations_for("    case value\n    in ^a then 1\n    end\n")

      expect(mutated_lines(muts)).to eq(["in a then 1"])
    end

    it "drops each pin of a pattern separately" do
      muts = mutations_for("    case value\n    in { id: ^a, tags: [^b, *] } then 1\n    end\n")

      expect(mutated_lines(muts)).to eq(
        ["in { id: a, tags: [^b, *] } then 1", "in { id: ^a, tags: [b, *] } then 1"]
      )
    end

    it "drops the pin of a rightward assignment" do
      muts = mutations_for("    value => [^a, rest]\n    rest\n")

      expect(mutated_lines(muts)).to eq(["value => [a, rest]"])
    end

    it "drops the pin of a pattern predicate" do
      muts = mutations_for("    value in ^a\n")

      expect(mutated_lines(muts)).to eq(["value in a"])
    end

    it "drops the pin inside a find pattern" do
      muts = mutations_for("    case value\n    in [*, ^a, *] then 1\n    end\n")

      expect(mutated_lines(muts)).to eq(["in [*, a, *] then 1"])
    end

    it "keeps the guard of the clause" do
      muts = mutations_for("    case value\n    in ^a if b then 1\n    end\n")

      expect(mutated_lines(muts)).to eq(["in a if b then 1"])
    end

    it "drops the pin of the implicit block parameter" do
      muts = mutations_for("    [a].map do\n      value in ^it\n    end\n")

      expect(mutated_lines(muts)).to eq(["value in it"])
    end

    # An alternative pattern may not capture, so the unpinned name does not
    # parse there; such a mutant says nothing about the tests.
    it "emits nothing for a pin inside an alternative pattern" do
      muts = mutations_for("    case value\n    in ^a | ^b then 1\n    end\n")

      expect(muts).to be_empty
    end

    it "emits nothing for a pin nested inside an alternative pattern" do
      muts = mutations_for("    case value\n    in [^a, 1] | { id: ^b } then 1\n    end\n")

      expect(muts).to be_empty
    end

    it "still drops a pin beside an alternative pattern" do
      muts = mutations_for("    case value\n    in [1 | 2, ^a] then 1\n    end\n")

      expect(mutated_lines(muts)).to eq(["in [1 | 2, a] then 1"])
    end

    it "emits nothing for a pinned numbered parameter" do
      muts = mutations_for("    [a].map do\n      value in ^_1\n    end\n")

      expect(muts).to be_empty
    end

    # Only a local name can stand as a capturing pattern; `in @expected` and
    # `in $expected` are not patterns at all.
    it "emits nothing for a pinned instance, class or global variable" do
      muts = mutations_for("    value in ^@expected\n    value in ^@@expected\n    value in ^$expected\n")

      expect(muts).to be_empty
    end

    it "emits nothing for a pinned expression" do
      muts = mutations_for("    case value\n    in ^(a + 1) then 1\n    end\n")

      expect(muts).to be_empty
    end

    it "emits nothing for a pattern without a pin" do
      muts = mutations_for("    case value\n    in [x, 1] then x\n    end\n")

      expect(muts).to be_empty
    end

    it "produces parseable mutations" do
      muts = mutations_for("    case value\n    in { id: ^a, tags: [^b, *] } then 1\n    in ^a | ^b then 2\n    end\n")

      expect(muts.map(&:parse_status)).to eq(%i[ok ok])
    end

    it "sets the operator name" do
      muts = mutations_for("    value in ^a\n")

      expect(muts.map(&:operator_name)).to eq(["pin_operator_removal"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["pinned_variable"])

      muts = mutations_for("    value in ^a\n", filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
