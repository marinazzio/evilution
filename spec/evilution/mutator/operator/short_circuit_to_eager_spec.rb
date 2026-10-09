# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ShortCircuitToEager do
  def mutations_of(body)
    Tempfile.create(["short_circuit_to_eager", ".rb"]) do |file|
      File.write(file.path, "class Sample\n  def value(a, b, c)\n#{body}  end\nend\n")
      described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)
    end
  end

  # The body of the method after each mutation.
  def mutated_bodies(body)
    mutations_of(body).map { |m| m.mutated_source.lines[2..-3].join }
  end

  describe "#call" do
    it "replaces && with &" do
      expect(mutated_bodies("    a && b\n")).to eq(["    a & b\n"])
    end

    it "replaces || with |" do
      expect(mutated_bodies("    a || b\n")).to eq(["    a | b\n"])
    end

    it "replaces the and / or keywords" do
      expect(mutated_bodies("    a and b\n")).to eq(["    a & b\n"])
      expect(mutated_bodies("    a or b\n")).to eq(["    a | b\n"])
    end

    it "leaves a named call or an index as an operand bare" do
      expect(mutated_bodies("    a.ready? && b[0]\n")).to eq(["    a.ready? & b[0]\n"])
      expect(mutated_bodies("    a.nil? || a.empty?\n")).to eq(["    a.nil? | a.empty?\n"])
    end

    # `&` and `|` bind tighter than a comparison: `a == 1 & b` is `a == (1 & b)`.
    it "parenthesizes an operand that would regroup" do
      expect(mutated_bodies("    a == 1 && b > 2\n")).to eq(["    (a == 1) & (b > 2)\n"])
      expect(mutated_bodies("    !a || b.nil?\n")).to eq(["    (!a) | b.nil?\n"])
      expect(mutated_bodies("    c = a and b\n")).to eq(["    (c = a) & b\n"])
    end

    it "keeps the meaning of the surrounding expression" do
      expect(mutated_bodies("    c = a && b\n")).to eq(["    c = a & b\n"])
      expect(mutated_bodies("    a && b ? 1 : 2\n")).to eq(["    a & b ? 1 : 2\n"])
      expect(mutated_bodies("    return 1 if a || b\n")).to eq(["    return 1 if a | b\n"])
    end

    it "mutates each operator of a chain in turn" do
      expect(mutated_bodies("    a && b && c\n")).to eq(["    (a && b) & c\n", "    a & b && c\n"])
      expect(mutated_bodies("    a || b && c\n")).to eq(["    a | (b && c)\n", "    a || b & c\n"])
    end

    it "joins operands written on two lines" do
      expect(mutated_bodies("    a.ready? &&\n      b.ready?\n")).to eq(["    a.ready? & b.ready?\n"])
    end

    # `a | (return)` does not parse: a jump has no value to pass on.
    it "leaves out an operand that only jumps" do
      expect(mutations_of("    a || return\n")).to be_empty
      expect(mutations_of("    [a].each { |x| x || next }\n")).to be_empty
    end

    it "keeps an operand that raises" do
      expect(mutated_bodies("    a || raise(ArgumentError)\n")).to eq(["    a | raise(ArgumentError)\n"])
    end

    it "leaves the bitwise operators alone" do
      expect(mutations_of("    a & b\n    a | b\n")).to be_empty
    end

    it "reports the mutation on the line of the expression" do
      expect(mutations_of("    c\n    a && b\n").map(&:line)).to eq([4])
    end

    it "produces valid Ruby" do
      bodies = ["    a && b\n", "    a == 1 && b > 2\n", "    c = a and b\n", "    a && b && c\n", "    record(a || b, !a && c)\n",
                "    a.ready? &&\n      b.ready?\n", "    a || raise(ArgumentError)\n", "    a && -> { b }\n", "    (yield a) || b\n"]
      mutations = bodies.flat_map { |body| mutations_of(body) }

      expect(mutations).not_to be_empty
      expect(mutations.map(&:parse_status)).to all(eq(:ok))
    end

    it "sets correct operator_name" do
      expect(mutations_of("    a && b\n").map(&:operator_name)).to eq(["short_circuit_to_eager"])
    end
  end
end
