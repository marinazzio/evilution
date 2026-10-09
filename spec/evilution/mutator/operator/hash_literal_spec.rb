# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::HashLiteral do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/hash_literal.rb", __dir__) }
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
    it "replaces { a: 1, b: 2 } with {}, nil, one hash per deleted pair and one per renamed key" do
      muts = mutations_for("returns_populated_hash")

      expect(muts.length).to eq(6)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def returns_populated_hash\s+\{\}\s+end/),
        a_string_matching(/def returns_populated_hash\s+nil\s+end/)
      )
    end

    it "produces no mutations for an empty hash" do
      muts = mutations_for("returns_empty_hash")

      expect(muts).to be_empty
    end

    it "recurses into hash elements to mutate a nested hash literal" do
      # `{ a: { b: 1 } }`: the outer hash yields 3 mutations and the nested
      # `{ b: 1 }` hash yields 3 more — only reached when the visitor recurses
      # into the hash elements.
      muts = mutations_for("returns_nested_hash")

      expect(muts.length).to eq(6)
      expect(muts.any? { |m| m.mutated_source.include?("{ a: {} }") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("{ a: nil }") }).to be true
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

    describe "pair deletion" do
      def mutations_of(body)
        Tempfile.create(["hash_literal", ".rb"]) do |file|
          File.write(file.path, "class Sample\n  def value(x)\n#{body}  end\nend\n")
          described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)
        end
      end

      # The body of the method after each mutation, without the two that
      # replace the hash as a whole.
      def deletions(body)
        mutations_of(body).drop(2).map { |m| m.mutated_source.lines[2..-3].join }.grep_v(/__evilution_mutated__/)
      end

      it "deletes each pair in turn, after {} and nil" do
        bodies = mutations_of("    { a: 1, b: 2, c: 3 }\n").first(5).map { |m| m.mutated_source.lines[2].strip }

        expect(bodies).to eq(["{}", "nil", "{ b: 2, c: 3 }", "{ a: 1, c: 3 }", "{ a: 1, b: 2 }"])
      end

      it "does not repeat the emptied hash for a single pair" do
        expect(deletions("    { a: 1 }\n")).to be_empty
      end

      it "deletes pairs written with a rocket or in shorthand" do
        expect(deletions("    { \"a\" => 1, x => 2 }\n")).to eq(["    { x => 2 }\n", "    { \"a\" => 1 }\n"])
        expect(deletions("    { x:, a: 1 }\n")).to eq(["    { a: 1 }\n", "    { x: }\n"])
      end

      it "deletes a pair next to a double splat, but not the splat" do
        expect(deletions("    { **x, a: 1 }\n")).to eq(["    { **x }\n"])
        expect(deletions("    { a: 1, **x, b: 2 }\n")).to eq(["    { **x, b: 2 }\n", "    { a: 1, **x }\n"])
      end

      it "keeps the layout and trailing comma of a multi-line hash" do
        body = "    {\n      a: 1,\n      b: 2,\n    }\n"

        expect(deletions(body)).to eq(["    {\n      b: 2,\n    }\n", "    {\n      a: 1,\n    }\n"])
      end

      it "reports each deletion on the line of its pair" do
        mutations = mutations_of("    {\n      a: 1,\n      b: 2,\n    }\n").drop(2).first(2)

        expect(mutations.map(&:line)).to eq([4, 5])
      end

      # The body of a heredoc sits after the closing brace, out of reach of
      # one cut.
      it "keeps a pair holding a heredoc and deletes the others" do
        expect(deletions("    { a: <<~ONE, b: x }\n      text\n    ONE\n")).to eq(["    { a: <<~ONE }\n      text\n    ONE\n"])
      end

      it "leaves the keywords of a call alone" do
        expect(mutations_of("    record(a: 1, b: 2)\n")).to be_empty
      end

      it "produces valid Ruby" do
        bodies = ["    { a: 1, b: 2, c: 3 }\n", "    { x:, a: 1, **x }\n",
                  "    { a: <<~ONE, b: x, c: <<~TWO }\n      one\n    ONE\n      two\n    TWO\n",
                  "    {\n      a: 1, # one\n      b: 2 # two\n    }\n"]
        mutations = bodies.flat_map { |body| mutations_of(body) }

        expect(mutations.map { |m| Prism.parse(m.mutated_source).success? }).to all(be(true))
      end
    end

    describe "key renaming" do
      def renames(body)
        Tempfile.create(["hash_literal", ".rb"]) do |file|
          File.write(file.path, "class Sample\n  def value(x)\n#{body}  end\nend\n")
          mutations = described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)
          mutations.map { |m| m.mutated_source.lines[2].strip }.grep(/__evilution_mutated__/)
        end
      end

      it "renames each label key in turn, after the deletions" do
        Tempfile.create(["hash_literal", ".rb"]) do |file|
          File.write(file.path, "class Sample\n  def value\n    { a: 1, b: 2 }\n  end\nend\n")
          mutations = described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)

          expect(mutations.map { |m| m.mutated_source.lines[2].strip }).to eq(
            ["{}", "nil", "{ b: 2 }", "{ a: 1 }", "{ __evilution_mutated__: 1, b: 2 }", "{ a: 1, __evilution_mutated__: 2 }"]
          )
        end
      end

      it "renames the key of a single pair" do
        expect(renames("    { a: 1 }\n")).to eq(["{ __evilution_mutated__: 1 }"])
      end

      it "renames a quoted label" do
        expect(renames("    { \"a b\": 1 }\n")).to eq(["{ __evilution_mutated__: 1 }"])
      end

      it "keeps the value of a shorthand pair" do
        expect(renames("    { x: }\n")).to eq(["{ __evilution_mutated__: x }"])
      end

      # SymbolLiteral and StringLiteral already replace these keys.
      it "leaves a key written with a rocket to the literal operators" do
        expect(renames("    { :a => 1, :\"a b\" => 1, \"b\" => 2, x => 3, 4 => 5 }\n")).to be_empty
      end

      it "leaves an interpolated label alone" do
        expect(renames("    { \"a\#{x}\": 1 }\n")).to be_empty
      end

      it "leaves the keywords of a call alone" do
        expect(renames("    record(a: 1)\n")).to be_empty
      end

      it "reports the rename on the line of its key" do
        Tempfile.create(["hash_literal", ".rb"]) do |file|
          File.write(file.path, "class Sample\n  def value\n    {\n      a: 1,\n      b: 2\n    }\n  end\nend\n")
          mutations = described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)

          expect(mutations.last(2).map(&:line)).to eq([4, 5])
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("returns_populated_hash")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("hash_literal")
      end
    end
  end
end
