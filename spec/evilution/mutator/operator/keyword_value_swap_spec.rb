# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::KeywordValueSwap do
  def mutations_for(body, filter: nil)
    tmpfile = Tempfile.new(["keyword_value_swap", ".rb"])
    tmpfile.write("class Caller < Base\n  def call(a, b, c, opts)\n#{body}  end\nend\n")
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

  # The method body of each mutant.
  def mutated_bodies(muts)
    muts.map { |m| m.mutated_source[/  def call\(.*?\)\n(.*)  end\nend\n\z/m, 1] }
  end

  describe "#call" do
    it "swaps the values of two keyword arguments" do
      muts = mutations_for("    compute(x: a, y: b)\n")

      expect(mutated_lines(muts)).to eq(["compute(x: b, y: a)"])
    end

    it "swaps the values of each adjacent pair of three keyword arguments" do
      muts = mutations_for("    compute(x: a, y: b, z: c)\n")

      expect(mutated_lines(muts)).to eq(["compute(x: b, y: a, z: c)", "compute(x: a, y: c, z: b)"])
    end

    it "keeps positional arguments, a block argument and the call shape in place" do
      expect(mutated_lines(mutations_for("    target.compute(a, x: b, y: c, &opts)\n"))).to eq(
        ["target.compute(a, x: c, y: b, &opts)"]
      )
      expect(mutated_lines(mutations_for("    compute x: a, y: b\n"))).to eq(["compute x: b, y: a"])
    end

    it "keeps the layout of keyword arguments spread over several lines" do
      muts = mutations_for("    compute(\n      x: a, # first\n      y: b\n    )\n")

      expect(mutated_bodies(muts)).to eq(["    compute(\n      x: b, # first\n      y: a\n    )\n"])
    end

    it "swaps values written with a hash rocket" do
      muts = mutations_for("    compute(\"x\" => a, \"y\" => b)\n")

      expect(mutated_lines(muts)).to eq(["compute(\"x\" => b, \"y\" => a)"])
    end

    # Shorthand keys have no value of their own to move, so the swap spells
    # both pairs out.
    it "spells out shorthand keys when swapping them" do
      expect(mutated_lines(mutations_for("    compute(a:, b:)\n"))).to eq(["compute(a: b, b: a)"])
      expect(mutated_lines(mutations_for("    compute(a:, y: c)\n"))).to eq(["compute(a: c, y: a)"])
    end

    it "swaps shorthand keys that name methods" do
      muts = mutations_for("    compute(size:, name:)\n")

      expect(mutated_lines(muts)).to eq(["compute(size: name, name: size)"])
    end

    it "swaps neighbours on either side of a double splat" do
      muts = mutations_for("    compute(x: a, **opts, y: b)\n")

      expect(mutated_lines(muts)).to eq(["compute(x: b, **opts, y: a)"])
    end

    it "swaps the keyword arguments of super and yield" do
      expect(mutated_lines(mutations_for("    super(x: a, y: b)\n"))).to eq(["super(x: b, y: a)"])
      expect(mutated_lines(mutations_for("    yield(x: a, y: b)\n"))).to eq(["yield(x: b, y: a)"])
    end

    it "swaps keyword arguments of a call nested in super or yield" do
      expect(mutated_lines(mutations_for("    super(wrap(x: a, y: b))\n"))).to eq(["super(wrap(x: b, y: a))"])
      expect(mutated_lines(mutations_for("    yield(wrap(x: a, y: b))\n"))).to eq(["yield(wrap(x: b, y: a))"])
    end

    it "swaps keyword arguments of calls nested in each other" do
      muts = mutations_for("    outer(x: inner(p: a, q: b), y: c)\n")

      expect(mutated_lines(muts)).to eq(
        ["outer(x: c, y: inner(p: a, q: b))", "outer(x: inner(p: b, q: a), y: c)"]
      )
    end

    # Swapping two identical values would reproduce the original call.
    it "skips a pair of identical values" do
      expect(mutations_for("    compute(x: a, y: a)\n")).to be_empty
      expect(mutated_lines(mutations_for("    compute(x: 1, y: 1, z: 2)\n"))).to eq(["compute(x: 1, y: 2, z: 1)"])
    end

    it "emits nothing for a single keyword argument" do
      expect(mutations_for("    compute(a, x: b)\n")).to be_empty
      expect(mutations_for("    compute(x: a, **opts)\n")).to be_empty
    end

    # A braced hash is one positional argument; its pairs are data, not
    # keyword arguments of the call.
    it "leaves a braced hash argument alone" do
      expect(mutations_for("    compute({ x: a, y: b })\n")).to be_empty
    end

    it "emits nothing for a call without keyword arguments" do
      expect(mutations_for("    compute(a, b)\n")).to be_empty
      expect(mutations_for("    compute\n")).to be_empty
    end

    it "produces parseable mutations" do
      muts = mutations_for("    compute(a:, b:, z: c)\n    super(x: a, \"y\" => b)\n")

      expect(muts.length).to eq(3)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "sets the operator name" do
      muts = mutations_for("    compute(x: a, y: b)\n")

      expect(muts.map(&:operator_name)).to eq(["keyword_value_swap"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=compute}"])

      muts = mutations_for("    compute(x: a, y: b)\n", filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
