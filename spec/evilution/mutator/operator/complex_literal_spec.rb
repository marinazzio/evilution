# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ComplexLiteral do
  def mutations_of(body)
    Tempfile.create(["complex_literal", ".rb"]) do |file|
      File.write(file.path, "class Sample\n  def value(x)\n#{body}  end\nend\n")
      described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)
    end
  end

  # The line each mutation of the given method body rewrote.
  def mutated_lines(body)
    mutations_of(body).map { |m| m.mutated_source.lines[m.line - 1].strip }
  end

  describe "#call" do
    it "replaces a complex literal with 0i, 1i, both neighbours and nil" do
      expect(mutated_lines("    5i\n")).to eq(%w[0i 1i 6i 4i nil])
    end

    it "does not replace 0i with itself" do
      expect(mutated_lines("    0i\n")).to eq(%w[1i -1i nil])
    end

    it "emits each replacement of 1i and 2i once" do
      expect(mutated_lines("    1i\n")).to eq(%w[0i 2i nil])
      expect(mutated_lines("    2i\n")).to eq(%w[0i 1i 3i nil])
    end

    it "replaces a negative literal as a whole" do
      expect(mutated_lines("    -2i\n")).to eq(%w[0i 1i -1i -3i nil])
    end

    it "keeps the neighbours of a float part floats" do
      expect(mutated_lines("    2.5i\n")).to eq(%w[0i 1i 3.5i 1.5i nil])
    end

    it "skips a replacement equal to a float part" do
      expect(mutated_lines("    1.0i\n")).to eq(%w[0i 2.0i nil])
      expect(mutated_lines("    0.0i\n")).to eq(%w[1i -1.0i nil])
    end

    it "leaves out the neighbours a float part is too large to tell apart" do
      expect(mutated_lines("    1e20i\n")).to eq(%w[0i 1i nil])
    end

    it "reads an integer part written in another base" do
      expect(mutated_lines("    0x10i\n")).to eq(%w[0i 1i 17i 15i nil])
    end

    # The neighbours of a rational part have no literal of their own in general.
    it "gives a rational part 0i, 1i and nil only" do
      expect(mutated_lines("    3ri\n")).to eq(%w[0i 1i nil])
    end

    it "replaces the literal inside an expression" do
      expect(mutated_lines("    x + 5i\n")).to eq(["x + 0i", "x + 1i", "x + 6i", "x + 4i", "x + nil"])
    end

    it "produces valid Ruby in a pattern and next to an operator" do
      bodies = ["    case x\n    in 5i then 1\n    in 0i..3i then 2\n    end\n", "    x-0i\n", "    record 0i, x\n"]
      mutations = bodies.flat_map { |body| mutations_of(body) }

      expect(mutations).not_to be_empty
      expect(mutations.map { |m| Prism.parse(m.mutated_source).success? }).to all(be(true))
    end

    it "sets correct operator_name" do
      expect(mutations_of("    5i\n").map(&:operator_name).uniq).to eq(["complex_literal"])
    end
  end
end
