# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RationalLiteral do
  def mutations_of(body)
    Tempfile.create(["rational_literal", ".rb"]) do |file|
      File.write(file.path, "class Sample\n  def value(x)\n#{body}  end\nend\n")
      described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)
    end
  end

  # The line each mutation of the given method body rewrote.
  def mutated_lines(body)
    mutations_of(body).map { |m| m.mutated_source.lines[m.line - 1].strip }
  end

  describe "#call" do
    it "replaces a rational literal with 0r, 1r, both neighbours and nil" do
      expect(mutated_lines("    5r\n")).to eq(%w[0r 1r 6r 4r nil])
    end

    it "does not replace 0r with itself" do
      expect(mutated_lines("    0r\n")).to eq(%w[1r -1r nil])
    end

    it "emits each replacement of 1r and 2r once" do
      expect(mutated_lines("    1r\n")).to eq(%w[0r 2r nil])
      expect(mutated_lines("    2r\n")).to eq(%w[0r 1r 3r nil])
    end

    it "replaces a negative literal as a whole" do
      expect(mutated_lines("    -2r\n")).to eq(%w[0r 1r -1r -3r nil])
    end

    it "writes the neighbours of a decimal literal as decimals" do
      expect(mutated_lines("    1.5r\n")).to eq(%w[0r 1r 2.5r 0.5r nil])
      expect(mutated_lines("    0.5r\n")).to eq(%w[0r 1r 1.5r -0.5r nil])
      expect(mutated_lines("    -0.25r\n")).to eq(%w[0r 1r 0.75r -1.25r nil])
    end

    it "keeps the leading zeros of a fraction" do
      expect(mutated_lines("    2.05r\n")).to eq(%w[0r 1r 3.05r 1.05r nil])
      expect(mutated_lines("    0.001r\n")).to eq(%w[0r 1r 1.001r -0.999r nil])
    end

    it "goes by the value, not by how the literal is written" do
      expect(mutated_lines("    1.50r\n")).to eq(%w[0r 1r 2.5r 0.5r nil])
      expect(mutated_lines("    1.0r\n")).to eq(%w[0r 2r nil])
      expect(mutated_lines("    0x10r\n")).to eq(%w[0r 1r 17r 15r nil])
    end

    it "replaces the literal inside an expression" do
      expect(mutated_lines("    x + 5r\n")).to eq(["x + 0r", "x + 1r", "x + 6r", "x + 4r", "x + nil"])
    end

    # ComplexLiteral replaces `3ri` as a whole; `nili` is not a value.
    it "leaves the rational part of a complex literal alone" do
      expect(mutated_lines("    3ri\n")).to be_empty
    end

    it "emits replacements that read back as the intended values" do
      values = mutations_of("    0.75r\n").map { |m| m.mutated_source.lines[2].strip }.first(4).map { |text| Rational(text.chomp("r")) }

      expect(values).to eq([0r, 1r, 1.75r, -0.25r])
    end

    it "produces valid Ruby in a pattern and next to an operator" do
      bodies = ["    case x\n    in 5r then 1\n    in 0r..3r then 2\n    end\n", "    x-0r\n", "    record 0.5r, x\n"]
      mutations = bodies.flat_map { |body| mutations_of(body) }

      expect(mutations).not_to be_empty
      expect(mutations.map { |m| Prism.parse(m.mutated_source).success? }).to all(be(true))
    end

    it "sets correct operator_name" do
      expect(mutations_of("    5r\n").map(&:operator_name).uniq).to eq(["rational_literal"])
    end
  end
end
