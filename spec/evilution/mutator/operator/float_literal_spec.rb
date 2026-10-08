# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::FloatLiteral do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/float_literal.rb", __dir__) }
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

  describe "#call" do
    it "replaces 0.0 with 1.0, the special values and nil" do
      muts = mutations_for("zero_float")

      expect(muts.length).to eq(5)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def zero_float\s+1\.0\s+end/),
        a_string_matching(/def zero_float\s+nil\s+end/)
      )
    end

    it "replaces 1.0 with 0.0, the special values and nil" do
      muts = mutations_for("one_float")

      expect(muts.length).to eq(5)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def one_float\s+0\.0\s+end/),
        a_string_matching(/def one_float\s+nil\s+end/)
      )
    end

    it "replaces 3.14 with 0.0, the special values and nil" do
      muts = mutations_for("pi_float")

      expect(muts.length).to eq(5)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def pi_float\s+0\.0\s+end/),
        a_string_matching(/def pi_float\s+nil\s+end/)
      )
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          expect { Prism.parse(mutation.mutated_source) }.not_to raise_error,
                                                                 "Invalid Ruby produced for #{mutation}"
        end
      end
    end

    describe "special values" do
      def mutations_of(body)
        Tempfile.create(["float_literal", ".rb"]) do |file|
          File.write(file.path, "class Sample\n  def value(x)\n#{body}  end\nend\n")
          described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)
        end
      end

      # The line each mutation of the given method body rewrote.
      def mutated_lines(body)
        mutations_of(body).map { |m| m.mutated_source.lines[m.line - 1].strip }
      end

      def all_parse?(body)
        mutations_of(body).all? { |m| Prism.parse(m.mutated_source).success? }
      end

      it "replaces a float with NaN and both infinities, before nil" do
        expect(mutated_lines("    3.14\n"))
          .to eq(["0.0", "Float::NAN", "Float::INFINITY", "-Float::INFINITY", "nil"])
      end

      it "replaces a negative float as a whole" do
        expect(mutated_lines("    -2.5\n"))
          .to eq(["0.0", "Float::NAN", "Float::INFINITY", "-Float::INFINITY", "nil"])
      end

      it "stays valid as an operand and as an argument without parentheses" do
        expect(mutated_lines("    x-1.5\n")).to include("x--Float::INFINITY")
        expect(all_parse?("    x-1.5\n")).to be(true)
        expect(all_parse?("    x**2.0\n")).to be(true)
        expect(all_parse?("    record 2.0, x\n")).to be(true)
      end

      # A pattern takes literals, not expressions: `in -Float::INFINITY` and
      # `in Float::NAN..2.0` do not parse.
      it "leaves the literals of a pattern to the other replacements" do
        expect(mutated_lines("    case x\n    in 2.5 then 1\n    end\n")).to eq(["in 0.0 then 1", "in nil then 1"])
        expect(mutated_lines("    case x\n    in [1.5..] then 1\n    end\n")).to eq(["in [0.0..] then 1", "in [nil..] then 1"])
        expect(mutated_lines("    x in { a: 2.5 }\n")).to eq(["x in { a: 0.0 }", "x in { a: nil }"])
        expect(mutated_lines("    x => 2.5\n")).to eq(["x => 0.0", "x => nil"])
      end

      it "still replaces a float in the guard of a pattern" do
        lines = mutated_lines("    case x\n    in Float if x > 2.5 then 1\n    end\n")

        expect(lines).to include("in Float if x > -Float::INFINITY then 1")
        expect(all_parse?("    case x\n    in Float if x > 2.5 then 1\n    end\n")).to be(true)
        expect(all_parse?("    case x\n    in Float unless x > 2.5 then 1\n    end\n")).to be(true)
      end

      it "still replaces a float in a pinned expression" do
        lines = mutated_lines("    case x\n    in ^(x + 2.5) then 1\n    end\n")

        expect(lines).to include("in ^(x + -Float::INFINITY) then 1")
        expect(all_parse?("    case x\n    in ^(x + 2.5) then 1\n    end\n")).to be(true)
      end

      it "still replaces a float in the value a pattern is matched against" do
        expect(mutated_lines("    (x + 2.5) in Float\n")).to include("(x + Float::NAN) in Float")
        expect(mutated_lines("    (x + 2.5) => Float\n")).to include("(x + Float::NAN) => Float")
      end

      it "still replaces a float in the body of a pattern branch" do
        expect(mutated_lines("    case x\n    in Float then 2.5\n    end\n")).to include("in Float then Float::NAN")
      end
    end

    # ComplexLiteral replaces the literal as a whole; `Float::NANi` is not a value.
    it "leaves the float part of a complex literal alone" do
      Tempfile.create(["float_literal", ".rb"]) do |file|
        File.write(file.path, "class Sample\n  def value\n    2.5i\n  end\nend\n")

        expect(described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)).to be_empty
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("zero_float")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("float_literal")
      end
    end
  end
end
