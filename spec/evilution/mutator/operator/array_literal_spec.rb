# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/array_literal"

RSpec.describe Evilution::Mutator::Operator::ArrayLiteral do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/array_literal.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:non_empty_subject) { subjects.find { |s| s.name.include?("returns_non_empty_array") } }
  let(:empty_subject) { subjects.find { |s| s.name.include?("returns_empty_array") } }

  describe "#call" do
    it "replaces [1, 2, 3] with [], nil and one array per deleted element" do
      mutations = described_class.new.call(non_empty_subject)

      expect(mutations.length).to eq(5)
      mutated_sources = mutations.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/\[\]/),
        a_string_matching(/nil/)
      )
    end

    it "does not mutate empty arrays" do
      mutations = described_class.new.call(empty_subject)

      expect(mutations).to be_empty
    end

    # Kills the `node.opening_loc` -> `node` change: an implicit array (the
    # bracket-less RHS of a multiple assignment) has a nil opening_loc and
    # must NOT be mutated; rewriting it would corrupt the assignment.
    it "does not mutate a bracket-less implicit array" do
      src = "class C\n  def m\n    a, b = 1, 2\n  end\nend"
      tmpfile = Tempfile.new(["arrlit", ".rb"])
      tmpfile.write(src)
      tmpfile.flush
      subjects = Evilution::AST::Parser.new.call(tmpfile.path)
      subj = subjects.find { |s| s.name.end_with?("#m") }

      expect(described_class.new.call(subj)).to be_empty
    ensure
      tmpfile&.close
      tmpfile&.unlink
    end

    it "produces valid Ruby for all mutations" do
      subjects.each do |subject|
        mutations = described_class.new.call(subject)
        mutations.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
        end
      end
    end

    describe "element deletion" do
      def mutations_of(body)
        Tempfile.create(["array_literal", ".rb"]) do |file|
          File.write(file.path, "class Sample\n  def value(x)\n#{body}  end\nend\n")
          described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)
        end
      end

      # The body of the method after each mutation, without the two that
      # replace the array as a whole.
      def deletions(body)
        mutations_of(body).drop(2).map { |m| m.mutated_source.lines[2..-3].join }
      end

      it "deletes each element in turn, after [] and nil" do
        bodies = mutations_of("    [1, 2, 3]\n").map { |m| m.mutated_source.lines[2].strip }

        expect(bodies).to eq(["[]", "nil", "[2, 3]", "[1, 3]", "[1, 2]"])
      end

      it "does not repeat the emptied array for a single element" do
        expect(deletions("    [1]\n")).to be_empty
        expect(deletions("    [a: 1, b: 2]\n")).to be_empty
      end

      it "deletes the words of a %w and %i array" do
        expect(deletions("    %w[a b c]\n")).to eq(["    %w[b c]\n", "    %w[a c]\n", "    %w[a b]\n"])
        expect(deletions("    %i[a b]\n")).to eq(["    %i[b]\n", "    %i[a]\n"])
      end

      it "deletes a splat and trailing keywords like any element" do
        expect(deletions("    [*x, 1]\n")).to eq(["    [1]\n", "    [*x]\n"])
        expect(deletions("    [1, a: 2]\n")).to eq(["    [a: 2]\n", "    [1]\n"])
      end

      it "keeps the layout and trailing comma of a multi-line array" do
        body = "    [\n      1,\n      2,\n    ]\n"

        expect(deletions(body)).to eq(["    [\n      2,\n    ]\n", "    [\n      1,\n    ]\n"])
      end

      it "deletes elements of a nested array on both levels" do
        lines = mutations_of("    [[1, 2], 3]\n").map { |m| m.mutated_source.lines[2].strip }

        expect(lines).to include("[3]", "[[1, 2]]", "[[2], 3]", "[[1], 3]")
      end

      # The body of a heredoc sits after the closing bracket, out of reach of
      # one cut.
      it "keeps a heredoc element and deletes the others" do
        expect(deletions("    [<<~ONE, x]\n      text\n    ONE\n")).to eq(["    [<<~ONE]\n      text\n    ONE\n"])
        expect(deletions("    [x, <<~ONE]\n      text\n    ONE\n")).to eq(["    [<<~ONE]\n      text\n    ONE\n"])
      end

      it "leaves a bracket-less array alone" do
        expect(mutations_of("    a, b = 1, 2\n    return a, b\n")).to be_empty
      end

      it "reports each deletion on the line of its element" do
        mutations = mutations_of("    [\n      1,\n      2,\n    ]\n").drop(2)

        expect(mutations.map(&:line)).to eq([4, 5])
      end

      it "produces valid Ruby" do
        bodies = ["    [1, 2, 3]\n", "    %w[a b c]\n", "    [*x, 1, a: 2]\n",
                  "    [<<~ONE, x, <<~TWO]\n      one\n    ONE\n      two\n    TWO\n",
                  "    [\n      1, # one\n      2 # two\n    ]\n"]
        mutations = bodies.flat_map { |body| mutations_of(body) }

        expect(mutations.map { |m| Prism.parse(m.mutated_source).success? }).to all(be(true))
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(non_empty_subject)

      expect(mutations.first.operator_name).to eq("array_literal")
    end
  end
end
