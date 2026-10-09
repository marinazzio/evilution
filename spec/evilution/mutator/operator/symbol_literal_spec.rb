# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::SymbolLiteral do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/symbol_literal.rb", __dir__) }
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
    it "replaces :foo with :__evilution_mutated__ and nil" do
      muts = mutations_for("returns_foo")

      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def returns_foo\s+:__evilution_mutated__\s+end/),
        a_string_matching(/def returns_foo\s+nil\s+end/)
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

    # RoundHalfModeSwap swaps the mode for the other two; a made-up symbol
    # only raises, and nil rounds like :up.
    it "leaves the half: mode of round to round_half_mode_swap" do
      expect(mutations_for("rounds_half_even")).to be_empty
    end

    it "still mutates other symbols next to a round mode" do
      muts = mutations_for("rounds_and_names")

      expect(muts.map { |m| m.mutated_source.lines[m.line - 1].strip }).to eq(
        ["[amount.round(2, half: :even), :__evilution_mutated__]", "[amount.round(2, half: :even), nil]"]
      )
    end

    it "mutates a half: value round does not accept" do
      expect(mutations_for("rounds_unknown_mode").length).to eq(2)
    end

    it "mutates a half: keyword of another method" do
      expect(mutations_for("half_keyword_elsewhere").length).to eq(2)
    end

    it "forgets the modes of an earlier subject" do
      operator = described_class.new
      subjects = subjects_from_fixture
      rounds = subjects.find { |s| s.name.end_with?("#rounds_half_even") }
      elsewhere = subjects.find { |s| s.name.end_with?("#half_keyword_elsewhere") }

      expect([operator.call(rounds).length, operator.call(elsewhere).length, operator.call(rounds).length]).to eq([0, 2, 0])
    end

    it "does not mutate keyword argument label keys" do
      muts = mutations_for("calls_with_kwarg")

      expect(muts).to be_empty
    end

    it "does not mutate hash label keys" do
      muts = mutations_for("uses_kwarg_label")

      expect(muts).to be_empty
    end

    it "still mutates standalone symbols in mixed argument lists" do
      muts = mutations_for("mixes_symbol_and_label")

      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to all(include("key: 3"))
    end

    it "still mutates symbols used with hash rocket syntax" do
      muts = mutations_for("uses_hash_rocket")

      expect(muts.length).to eq(2)
    end

    it "mutates a quoted symbol literal (closing is a quote, not a label colon)" do
      tmpfile = Tempfile.new(["symbol_literal_quoted", ".rb"])
      tmpfile.write("class C\n  def quoted_symbol\n    :\"foo bar\"\n  end\nend\n")
      tmpfile.close
      file_src = File.read(tmpfile.path)
      file_tree = Prism.parse(file_src).value
      finder = Evilution::AST::SubjectFinder.new(file_src, tmpfile.path)
      finder.visit(file_tree)
      quoted_subject = finder.subjects.find { |s| s.name.end_with?("#quoted_symbol") }

      muts = described_class.new.call(quoted_subject)

      expect(muts.length).to eq(2)
      expect(muts.map(&:mutated_source)).to include(
        a_string_matching(/:__evilution_mutated__/),
        a_string_matching(/def quoted_symbol\s+nil\s+end/)
      )
    ensure
      tmpfile.unlink if tmpfile
    end

    # `"b": 2` closes with `":`; `:__evilution_mutated__ 2` does not parse.
    it "does not mutate quoted label keys" do
      Tempfile.create(["symbol_literal", ".rb"]) do |file|
        File.write(file.path, "class Sample\n  def value\n    record({ \"a b\": 1 }, \"c d\": 2)\n  end\nend\n")

        expect(described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)).to be_empty
      end
    end

    describe "interpolated symbol as a whole" do
      def mutations_of(body)
        Tempfile.create(["symbol_literal", ".rb"]) do |file|
          File.write(file.path, "class Sample\n  def value(x)\n#{body}  end\nend\n")
          described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)
        end
      end

      def mutated_lines(body)
        mutations_of(body).map { |m| m.mutated_source.lines[2].strip }
      end

      it "produces valid Ruby" do
        bodies = ["    :\"visit_\#{x}\"\n", "    send(:\"visit_\#{x}\", x)\n", "    :\"a\#{x || :b}\"\n",
                  "    { \"a\#{x}\": :b }\n", "    %I[a\#{x} b]\n"]
        mutations = bodies.flat_map { |body| mutations_of(body) }

        expect(mutations).not_to be_empty
        expect(mutations.map(&:parse_status)).to all(eq(:ok))
      end

      it "replaces the whole symbol with the empty symbol and nil" do
        expect(mutated_lines("    :\"visit_\#{x}\"\n")).to eq([':""', "nil"])
      end

      it "replaces the symbol inside an expression" do
        expect(mutated_lines("    send(:\"visit_\#{x}\", x)\n")).to eq(['send(:"", x)', "send(nil, x)"])
      end

      it "still mutates a symbol inside the interpolation" do
        expect(mutated_lines("    :\"a\#{x || :b}\"\n"))
          .to eq([':""', "nil", ":\"a\#{x || :__evilution_mutated__}\"", ":\"a\#{x || nil}\""])
      end

      it "leaves an interpolated label key alone" do
        expect(mutated_lines("    { \"a\#{x}\": 1 }\n")).to be_empty
        expect(mutated_lines("    record(\"a\#{x}\": 1)\n")).to be_empty
      end

      # A word of `%I[]` is not a literal of its own: `nil` there is the symbol :nil.
      it "does not replace a word of a %I array as a whole" do
        expect(mutated_lines("    %I[a\#{x} b]\n")).not_to include('%I[:"" b]', "%I[nil b]")
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("returns_foo")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("symbol_literal")
      end
    end
  end
end
