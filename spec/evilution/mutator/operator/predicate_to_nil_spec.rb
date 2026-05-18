# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::PredicateToNil do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/predicate_to_nil.rb", __dir__) }
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

  def mutations_from_source(inline_source)
    tmpfile = Tempfile.new(["predicate_to_nil", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "replaces simple predicate with nil" do
      muts = mutations_for("simple_predicate")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("nil")
      expect(muts.first.mutated_source).not_to include("x.empty?")
    end

    it "replaces predicate-with-receiver with nil" do
      muts = mutations_for("predicate_with_receiver")

      expect(muts.length).to eq(1)
      replacement = muts.first.diff.lines.select { |l| l.start_with?("+") }.join
      expect(replacement).to include("nil")
    end

    it "replaces bare predicate with nil" do
      muts = mutations_for("bare_predicate")

      expect(muts.length).to eq(1)
    end

    it "replaces nil? check with nil" do
      muts = mutations_for("nil_check")

      expect(muts.length).to eq(1)
    end

    it "replaces predicate-with-block with nil" do
      muts = mutations_for("predicate_with_block")

      expect(muts.length).to eq(1)
    end

    it "skips non-predicate methods" do
      muts = mutations_for("non_predicate_method")

      expect(muts).to be_empty
    end

    it "recurses into a nested predicate receiver so the inner predicate is also replaced" do
      muts = mutations_from_source("class C\n  def m(a)\n    a.b?.c?\n  end\nend\n")

      # one nil-mutation for the outer c? + one for the receiver b?
      expect(muts.length).to eq(2)
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty,
                                   "Invalid Ruby produced for #{mutation}: #{result.errors.map(&:message)}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("simple_predicate")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("predicate_to_nil")
      end
    end
  end
end
