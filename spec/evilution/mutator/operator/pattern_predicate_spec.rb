# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::PatternPredicate do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/pattern_predicate.rb", __dir__) }
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
    tmpfile = Tempfile.new(["pattern_predicate", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "replaces a predicate used as an if condition" do
      muts = mutations_for("as_if_predicate")

      expect(muts.map { |m| m.mutated_slice.strip }).to eq(["if false"])
    end

    it "replaces a predicate assigned to a local" do
      muts = mutations_for("as_value")

      expect(muts.map { |m| m.mutated_slice.strip }).to eq(["flag = (false)"])
    end

    # `in` binds looser than `=`, so an unparenthesised `flag = x in Integer`
    # is really `(flag = x) in Integer` and the predicate owns the assignment.
    # Replacing it therefore drops the assignment as well.
    it "replaces the assignment too when the predicate is unparenthesised" do
      muts = mutations_for("unparenthesised_value")

      expect(muts.map { |m| m.mutated_slice.strip }).to eq(["false"])
    end

    it "replaces a predicate in return position" do
      muts = mutations_for("as_return")

      expect(muts.map { |m| m.mutated_slice.strip }).to eq(["return (false)"])
    end

    it "replaces a predicate inside a block" do
      muts = mutations_for("in_block")

      expect(muts.map { |m| m.mutated_slice.strip }).to eq(["items.select { |item| false }"])
    end

    it "replaces a predicate whose pattern binds a name" do
      muts = mutations_for("with_binding")

      expect(muts.map { |m| m.mutated_slice.strip }).to eq(["if false"])
    end

    it "replaces a destructuring predicate whole" do
      muts = mutations_for("destructuring")

      expect(muts.map { |m| m.mutated_slice.strip }).to eq(["false"])
    end

    it "replaces only the pattern half of a compound condition" do
      muts = mutations_for("combined")

      expect(muts.map { |m| m.mutated_slice.strip }).to eq(["(false) && flag"])
    end

    it "replaces each predicate of a two-predicate expression separately" do
      muts = mutations_for("two_predicates")

      expect(muts.map { |m| m.mutated_slice.strip }).to contain_exactly(
        "(false) || (y in String)", "(x in Integer) || (false)"
      )
    end

    it "descends into a predicate nested inside another predicate's value" do
      muts = mutations_for("nested_predicates")

      expect(muts.map { |m| m.mutated_slice.strip }).to contain_exactly(
        "false", "items.map { |i| false } in [true, *]"
      )
    end

    # `x => Integer` is a MatchRequiredNode: it raises instead of returning a
    # boolean, so `false` is not a meaning-preserving substitution for it.
    it "leaves a rightward-assignment pattern alone" do
      muts = mutations_for("required_match")

      expect(muts).to be_empty
    end

    it "emits nothing for a method without pattern predicates" do
      muts = mutations_for("no_pattern")

      expect(muts).to be_empty
    end

    it "reports the mutation on the line of the predicate" do
      muts = mutations_for("as_value")

      expect(muts.map(&:line)).to eq([13])
    end

    it "names the operator" do
      muts = mutations_for("as_value")

      expect(muts.map(&:operator_name)).to eq(["pattern_predicate"])
    end

    it "produces valid Ruby for every mutation" do
      subjects_from_fixture.each do |subj|
        described_class.new.call(subj).each do |mutation|
          expect(Prism.parse(mutation.mutated_source).errors).to be_empty,
                                                                 "invalid Ruby: #{mutation.diff}"
        end
      end
    end

    it "descends into a predicate nested inside a block inside a conditional" do
      muts = mutations_from_source(
        "def nested(items, x)\n  if x in Integer\n    items.select { |i| i in String }\n  end\nend\n"
      )

      expect(muts.length).to eq(2)
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["match_predicate"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#as_value") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
