# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BitwiseReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/bitwise.rb", __dir__) }
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
    it "replaces & with | and ^" do
      muts = mutations_for("bitwise_and")

      expect(muts.length).to eq(2)
      expect(muts.map(&:mutated_source)).to include(
        a_string_including("a | b"),
        a_string_including("a ^ b")
      )
    end

    it "replaces | with & and ^" do
      muts = mutations_for("bitwise_or")

      expect(muts.length).to eq(2)
      expect(muts.map(&:mutated_source)).to include(
        a_string_including("a & b"),
        a_string_including("a ^ b")
      )
    end

    it "replaces ^ with & and |" do
      muts = mutations_for("bitwise_xor")

      expect(muts.length).to eq(2)
      expect(muts.map(&:mutated_source)).to include(
        a_string_including("a & b"),
        a_string_including("a | b")
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

    it "sets correct operator_name" do
      muts = mutations_for("bitwise_and")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("bitwise_replacement")
      end
    end

    it "does not mutate methods with no bitwise operators" do
      plain_source = "class Foo\n  def greet\n    'hello'\n  end\nend"
      plain_path = fixture_path
      tree = Prism.parse(plain_source).value
      finder = Evilution::AST::SubjectFinder.new(plain_source, plain_path)
      finder.visit(tree)
      subj = finder.subjects.find { |s| s.name.end_with?("#greet") }

      muts = described_class.new.call(subj)
      expect(muts).to be_empty
    end

    def mutations_for_source(src, method_name)
      tmpfile = Tempfile.new(["bitwise", ".rb"])
      tmpfile.write(src)
      tmpfile.flush
      subjects = Evilution::AST::Parser.new.call(tmpfile.path)
      subj = subjects.find { |s| s.name.end_with?("##{method_name}") }
      described_class.new.call(subj)
    ensure
      tmpfile&.close
      tmpfile&.unlink
    end

    # Kills the `return super unless replacements` guard removal: a
    # non-bitwise call has no REPLACEMENTS entry and must not raise
    # (a deleted guard would call `nil.each`).
    it "leaves non-bitwise calls untouched without raising" do
      src = "class C\n  def m(a)\n    a.upcase\n  end\nend"

      expect { mutations_for_source(src, "m") }.not_to raise_error
      expect(mutations_for_source(src, "m")).to be_empty
    end

    # Kills the `return super` -> bare `return` change: traversal must still
    # descend into a non-bitwise call's arguments to find nested bitwise ops.
    it "mutates bitwise operators nested inside a non-bitwise call's arguments" do
      muts = mutations_for_source("class C\n  def m(a, b)\n    puts(a & b)\n  end\nend", "m")

      expect(muts.length).to eq(2)
      expect(muts.map(&:mutated_source)).to include(
        a_string_including("puts(a | b)"),
        a_string_including("puts(a ^ b)")
      )
    end

    # Kills the trailing `super` deletion: traversal must descend into a
    # bitwise call nested inside another bitwise call.
    it "mutates bitwise operators nested inside other bitwise expressions" do
      muts = mutations_for_source("class C\n  def m(a, b, c)\n    a & (b | c)\n  end\nend", "m")

      sources = muts.map(&:mutated_source)
      expect(sources).to include(a_string_including("b & c"))
    end
  end
end
