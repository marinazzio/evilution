# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::CaseIn do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/case_in.rb", __dir__) }
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

  # The clause each mutation removed, read off the diff's deleted lines.
  def removed_clauses(muts)
    muts.map do |mutation|
      mutation.diff.lines.grep(/^-/).map { |line| line.sub(/^-\s*/, "").strip }.join("; ")
    end
  end

  # An else removal deletes the `else` keyword; a clause removal never does.
  def else_removals(muts)
    muts.select { |m| m.diff.match?(/^-\s+else$/) }
  end

  def clause_removals(muts)
    muts - else_removals(muts)
  end

  # mutated_source is the whole fixture file, and several methods there share
  # literals, so assertions have to look at the mutated method alone.
  def mutated_body(mutation, method_name)
    mutation.mutated_source[/  def #{method_name}\b.*?\n  end\n/m]
  end

  def mutations_from_source(inline_source)
    tmpfile = Tempfile.new(["case_in", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "removes each in-clause of a two-clause case in turn" do
      muts = mutations_for("two_clauses")

      expect(removed_clauses(muts)).to contain_exactly("in Integer; :int", "in String; :str")
    end

    it "removes in-clauses without touching the else branch" do
      muts = clause_removals(mutations_for("with_else"))

      expect(muts.length).to eq(2)
      muts.each do |mutation|
        expect(mutation.mutated_source).to include("else\n      :other")
      end
    end

    it "emits nothing for a lone in-clause, which cannot be dropped" do
      muts = mutations_for("single_clause")

      expect(muts).to be_empty
    end

    it "removes a guard along with the clause it belongs to" do
      muts = mutations_for("guarded_clause")

      expect(removed_clauses(muts)).to include("in [1, *rest] if rest.any?; rest")
    end

    it "removes a one-line then-form clause" do
      muts = mutations_for("then_form")

      expect(removed_clauses(muts)).to contain_exactly("in Integer then :int", "in String then :str")
    end

    it "removes a clause whose body is empty" do
      muts = mutations_for("empty_body_clause")

      expect(removed_clauses(muts)).to include("in Integer")
    end

    it "removes a destructuring clause whole" do
      muts = mutations_for("destructuring")

      expect(removed_clauses(muts)).to include("in {name: String => name, age: Integer}; name")
    end

    it "descends into a case/in nested inside a clause body" do
      muts = mutations_for("nested")

      expect(removed_clauses(muts)).to include("in Symbol; :sym", "in Float; :float")
    end

    it "removes the else branch of a case/in" do
      muts = else_removals(mutations_for("with_else"))

      expect(muts.length).to eq(1)
      expect(mutated_body(muts.first, "with_else")).to eq(
        "  def with_else(x)\n    case x\n    in Integer\n      :int\n    " \
        "in String\n      :str\n    \n    end\n  end\n"
      )
    end

    it "takes a multi-statement else body with it" do
      muts = else_removals(mutations_for("multi_statement_else"))

      expect(muts.length).to eq(1)
      expect(mutated_body(muts.first, "multi_statement_else")).not_to include("log(x)")
    end

    # A case/when falls through an empty else to nil either way, so CaseWhen
    # skips that shape. A case/in without an else raises instead, so removing
    # an empty one is a real behaviour change.
    it "removes an empty else, which is not a no-op for case/in" do
      muts = else_removals(mutations_for("empty_else"))

      expect(mutated_body(muts.first, "empty_else")).to eq(
        "  def empty_else(x)\n    case x\n    in Integer\n      :int\n    \n    end\n  end\n"
      )
    end

    it "removes the else even when a lone in-clause blocks clause removal" do
      muts = mutations_for("single_clause_with_else")

      expect(muts.length).to eq(1)
      expect(else_removals(muts).length).to eq(1)
    end

    it "emits no else mutation when there is no else" do
      muts = else_removals(mutations_for("two_clauses"))

      expect(muts).to be_empty
    end

    it "reports the mutation on the line of the clause it removes" do
      muts = mutations_for("two_clauses")

      expect(muts.map(&:line)).to contain_exactly(6, 8)
    end

    it "names the operator" do
      muts = mutations_for("two_clauses")

      expect(muts.map(&:operator_name).uniq).to eq(["case_in"])
    end

    it "produces valid Ruby for every mutation" do
      subjects_from_fixture.each do |subj|
        described_class.new.call(subj).each do |mutation|
          expect(Prism.parse(mutation.mutated_source).errors).to be_empty,
                                                                 "invalid Ruby: #{mutation.diff}"
        end
      end
    end

    it "emits nothing for a case/when, which has no in-clauses" do
      muts = mutations_from_source(
        "def plain(x)\n  case x\n  when 1 then :a\n  when 2 then :b\n  end\nend\n"
      )

      expect(muts).to be_empty
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["in"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#two_clauses") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(2)
    end
  end
end
