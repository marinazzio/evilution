# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ArgumentOrderPermutation do
  def mutations_for(body, signature: "a, b, c", filter: nil)
    tmpfile = Tempfile.new(["argument_order_permutation", ".rb"])
    tmpfile.write("class Caller < Base\n  def call(#{signature})\n#{body}  end\nend\n")
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
    it "swaps the two arguments of a call" do
      muts = mutations_for("    compute(a, b)\n")

      expect(mutated_lines(muts)).to eq(["compute(b, a)"])
    end

    it "swaps each adjacent pair of three arguments" do
      muts = mutations_for("    compute(a, b, c)\n")

      expect(mutated_lines(muts)).to eq(["compute(b, a, c)", "compute(a, c, b)"])
    end

    it "swaps the arguments of a call with a receiver and without parentheses" do
      expect(mutated_lines(mutations_for("    target.compute(a, b)\n"))).to eq(["target.compute(b, a)"])
      expect(mutated_lines(mutations_for("    compute a, b\n"))).to eq(["compute b, a"])
    end

    it "keeps the layout of arguments spread over several lines" do
      muts = mutations_for("    compute(\n      a, # first\n      b\n    )\n")

      expect(mutated_bodies(muts)).to eq(["    compute(\n      b, # first\n      a\n    )\n"])
    end

    it "swaps the arguments of super and yield" do
      expect(mutated_lines(mutations_for("    super(a, b)\n"))).to eq(["super(b, a)"])
      expect(mutated_lines(mutations_for("    yield(a, b)\n"))).to eq(["yield(b, a)"])
    end

    it "swaps the arguments of a call nested in super or yield" do
      expect(mutated_lines(mutations_for("    super(wrap(a, b))\n"))).to eq(["super(wrap(b, a))"])
      expect(mutated_lines(mutations_for("    yield(wrap(a, b))\n"))).to eq(["yield(wrap(b, a))"])
    end

    it "swaps the arguments of an index read" do
      muts = mutations_for("    a[0, 3]\n")

      expect(mutated_lines(muts)).to eq(["a[3, 0]"])
    end

    it "swaps the arguments of calls nested in each other" do
      muts = mutations_for("    outer(inner(a, b), c)\n")

      expect(mutated_lines(muts)).to eq(["outer(c, inner(a, b))", "outer(inner(b, a), c)"])
    end

    it "keeps keyword arguments and a block argument in place" do
      muts = mutations_for("    compute(a, b, strict: true, &c)\n")

      expect(mutated_lines(muts)).to eq(["compute(b, a, strict: true, &c)"])
    end

    it "emits nothing for a single positional argument" do
      expect(mutations_for("    compute(a)\n")).to be_empty
      expect(mutations_for("    compute(a, strict: b)\n")).to be_empty
    end

    # A splat stands for an unknown number of arguments, so a value swapped
    # with it would not land where the original stood.
    it "leaves a splat and its neighbours in place" do
      expect(mutations_for("    compute(*a, b)\n")).to be_empty
      expect(mutated_lines(mutations_for("    compute(a, b, *c)\n"))).to eq(["compute(b, a, *c)"])
    end

    it "emits nothing for forwarded arguments" do
      expect(mutations_for("    compute(...)\n", signature: "...")).to be_empty
    end

    # Swapping two identical arguments would reproduce the original call.
    it "skips a pair of identical arguments" do
      expect(mutations_for("    compute(a, a)\n")).to be_empty
      expect(mutated_lines(mutations_for("    compute(1, 1, 2)\n"))).to eq(["compute(1, 2, 1)"])
    end

    # `raise ArgumentError, "message"` reversed raises TypeError wherever it is
    # reached, which only shows that the line ran.
    it "leaves raise and fail alone" do
      expect(mutations_for("    raise ArgumentError, a\n")).to be_empty
      expect(mutations_for("    fail ArgumentError, a\n")).to be_empty
    end

    # The format string swapped with a value raises TypeError wherever it is
    # reached; what the string itself renders is FormatSpecifierSwap's job.
    it "leaves format, sprintf and printf alone" do
      expect(mutations_for("    format(\"%d %d\", a, b)\n")).to be_empty
      expect(mutations_for("    sprintf(\"%d %d\", a, b)\n")).to be_empty
      expect(mutations_for("    printf(\"%d %d\", a, b)\n")).to be_empty
    end

    it "swaps the arguments of a format method sent to a receiver" do
      expect(mutated_lines(mutations_for("    a.format(b, c)\n"))).to eq(["a.format(c, b)"])
    end

    it "swaps the arguments of a raise sent to a receiver" do
      muts = mutations_for("    a.raise(b, c)\n")

      expect(mutated_lines(muts)).to eq(["a.raise(c, b)"])
    end

    # These core methods treat their arguments as an unordered set of
    # alternatives, so any order gives the same answer.
    it "leaves calls whose arguments are alternatives alone" do
      expect(mutations_for("    a.start_with?(b, c)\n")).to be_empty
      expect(mutations_for("    a.end_with?(b, c)\n")).to be_empty
      expect(mutations_for("    Set[a, b]\n")).to be_empty
      expect(mutations_for("    ::Set[a, b]\n")).to be_empty
    end

    it "still swaps the index arguments of a receiver other than Set" do
      expect(mutated_lines(mutations_for("    Other[a, b]\n"))).to eq(["Other[b, a]"])
      expect(mutated_lines(mutations_for("    Mine::Set[a, b]\n"))).to eq(["Mine::Set[b, a]"])
      expect(mutated_lines(mutations_for("    ::Other[a, b]\n"))).to eq(["::Other[b, a]"])
    end

    it "still swaps the arguments of other methods called on Set" do
      expect(mutated_lines(mutations_for("    Set.build(a, b)\n"))).to eq(["Set.build(b, a)"])
    end

    # OptionParser sorts the arguments of #on by their shape; a method named
    # `on` is too common to skip by name, so projects silence it themselves.
    it "can be silenced for OptionParser#on with an ignore pattern" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=on, receiver=local_variable_read{name=opts}}"])

      muts = mutations_for(
        "    opts.on(\"-j\", \"--jobs N\", Integer)\n    other.on(a, b)\n", signature: "opts, a, b", filter: filter
      )

      expect(mutated_lines(muts)).to eq(["other.on(b, a)"])
    end

    # The last argument of an index write is the value being stored, not a
    # peer of the index.
    it "leaves an index write alone" do
      expect(mutations_for("    a[b, c] = 1\n")).to be_empty
    end

    it "emits nothing for a call without arguments" do
      expect(mutations_for("    compute\n")).to be_empty
    end

    it "produces parseable mutations" do
      muts = mutations_for("    outer(inner(a, b), c)\n    super(a, b)\n    a[0, 3]\n")

      expect(muts.length).to eq(4)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "sets the operator name" do
      muts = mutations_for("    compute(a, b)\n")

      expect(muts.map(&:operator_name)).to eq(["argument_order_permutation"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=compute}"])

      muts = mutations_for("    compute(a, b)\n", filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
