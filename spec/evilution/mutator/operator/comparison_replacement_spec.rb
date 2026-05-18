# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ComparisonReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/comparison.rb", __dir__) }
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
    it "replaces >= with >, ==, and <=" do
      muts = mutations_for("adult?")
      replacements = muts.map(&:mutated_source)

      expect(muts.length).to eq(3)
      expect(replacements).to include(
        a_string_including("> 18"),
        a_string_including("== 18"),
        a_string_including("<= 18")
      )
    end

    it "replaces > with >=, ==, and < and replaces < with <=, ==, and >" do
      muts = mutations_for("teenager?")

      expect(muts.length).to eq(6)
    end

    it "replaces == with !=" do
      muts = mutations_for("equal_check")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("!=")
    end

    it "replaces != with ==" do
      muts = mutations_for("not_equal_check")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("==")
    end

    it "replaces <= with <, ==, and >=" do
      muts = mutations_for("at_most?")

      expect(muts.length).to eq(3)
      replacements = muts.map(&:mutated_source)
      expect(replacements).to include(
        a_string_including("< limit"),
        a_string_including("== limit"),
        a_string_including(">= limit")
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
      muts = mutations_for("adult?")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("comparison_replacement")
      end
    end

    def mutations_for_source(src, method_name)
      tmpfile = Tempfile.new(["comparison", ".rb"])
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
    # non-comparison call has no REPLACEMENTS entry and must not raise
    # (a deleted guard would call `nil.each`).
    it "leaves non-comparison calls untouched without raising" do
      src = "class C\n  def m(a)\n    a.upcase\n  end\nend"

      expect { mutations_for_source(src, "m") }.not_to raise_error
      expect(mutations_for_source(src, "m")).to be_empty
    end

    # Kills the `return super` -> bare `return` change: traversal must still
    # descend into a non-comparison call's arguments.
    it "mutates comparisons nested inside a non-comparison call's arguments" do
      muts = mutations_for_source("class C\n  def m(a, b)\n    puts(a > b)\n  end\nend", "m")

      expect(muts.length).to eq(3)
      expect(muts.map(&:mutated_source)).to include(a_string_including("puts(a >= b)"))
    end

    # Kills the trailing `super` deletion: traversal must descend into a
    # comparison nested inside another comparison expression.
    it "mutates comparisons nested inside other comparisons" do
      muts = mutations_for_source("class C\n  def m(a, b, c)\n    a == (b > c)\n  end\nend", "m")

      sources = muts.map(&:mutated_source)
      expect(sources).to include(a_string_including("b >= c"))
    end
  end

  def source_diff(mutation)
    mutation.mutated_source
  end
end
