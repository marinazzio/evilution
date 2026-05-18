# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ArithmeticReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/arithmetic.rb", __dir__) }
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
    it "replaces + with -" do
      muts = mutations_for("add")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a - b")
    end

    it "replaces - with +" do
      muts = mutations_for("subtract")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a + b")
    end

    it "replaces * with /" do
      muts = mutations_for("multiply")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a / b")
    end

    it "replaces / with *" do
      muts = mutations_for("divide")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a * b")
    end

    it "replaces % with *" do
      muts = mutations_for("modulo")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a * b")
    end

    it "replaces ** with *" do
      muts = mutations_for("power")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a * b")
    end

    it "replaces << with >>" do
      muts = mutations_for("left_shift")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a >> b")
    end

    it "replaces >> with <<" do
      muts = mutations_for("right_shift")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a << b")
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
      muts = mutations_for("add")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("arithmetic_replacement")
      end
    end

    it "does not mutate methods with no arithmetic operators" do
      # Build a subject from a source with no arithmetic
      plain_source = "class Foo\n  def greet\n    'hello'\n  end\nend"
      plain_path = fixture_path # reuse path for SubjectFinder, source is what matters
      tree = Prism.parse(plain_source).value
      finder = Evilution::AST::SubjectFinder.new(plain_source, plain_path)
      finder.visit(tree)
      subj = finder.subjects.find { |s| s.name.end_with?("#greet") }

      muts = described_class.new.call(subj)
      expect(muts).to be_empty
    end

    def mutations_for_source(src, method_name)
      tmpfile = Tempfile.new(["arith", ".rb"])
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
    # non-arithmetic call (no entry in REPLACEMENTS) must produce no
    # mutations and must not raise (a deleted guard would `nil.each`).
    it "leaves non-arithmetic calls untouched without raising" do
      src = "class C\n  def m(a)\n    a.upcase\n  end\nend"

      expect { mutations_for_source(src, "m") }.not_to raise_error
      expect(mutations_for_source(src, "m")).to be_empty
    end

    # Kills the `return super` -> bare `return` change: the recursive
    # traversal must still descend into a non-arithmetic call's arguments
    # so a nested arithmetic operator is found.
    it "mutates arithmetic nested inside a non-arithmetic call's arguments" do
      muts = mutations_for_source("class C\n  def m(a, b)\n    puts(a + b)\n  end\nend", "m")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("puts(a - b)")
    end

    # Kills the trailing `super` deletion: traversal must descend into a
    # nested arithmetic call (the `*` inside the `+`'s argument).
    it "mutates arithmetic operators nested inside other arithmetic" do
      muts = mutations_for_source("class C\n  def m(a, b, c)\n    a + b * c\n  end\nend", "m")

      sources = muts.map(&:mutated_source)
      expect(sources).to include(a_string_including("a - b * c"))
      expect(sources).to include(a_string_including("a + b / c"))
    end
  end
end
