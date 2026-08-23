# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::CaseWhen do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/case_when.rb", __dir__) }
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

  def mutations_from_source(method_name, src)
    tmpfile = Tempfile.new(["case_when", ".rb"])
    tmpfile.write(src)
    tmpfile.close
    subj = Evilution::AST::Parser.new.call(tmpfile.path)
                                 .find { |s| s.name.end_with?("##{method_name}") }
    described_class.new.call(subj)
  ensure
    tmpfile.unlink if tmpfile
  end

  describe "#call" do
    context "when branch removal" do
      it "removes each when branch from a multi-branch case" do
        muts = mutations_for("simple_case")
        branch_removals = muts.select { |m| m.diff.match?(/^-\s+when\s/) }

        expect(branch_removals.length).to eq(2)
      end

      it "does not remove when from a single-when case" do
        muts = mutations_for("single_when")
        branch_removals = muts.select { |m| m.diff.match?(/^-\s+when\s/) }

        expect(branch_removals).to be_empty
      end
    end

    context "when body replacement" do
      it "replaces when body with nil" do
        muts = mutations_for("simple_case")
        nil_replacements = muts.select { |m| m.diff.include?("+ ") && m.diff.include?("nil") }

        expect(nil_replacements.length).to be >= 2
      end

      it "replaces multiline when body with nil" do
        muts = mutations_for("case_with_multiline_body")
        nil_replacements = muts.select { |m| m.diff.include?("nil") }

        expect(nil_replacements).not_to be_empty
      end

      it "skips body replacement for empty when branches" do
        muts = mutations_for("case_with_empty_when")
        # when 1 has no body - should not get body replacement for it
        # when 2 has body - should get body replacement
        nil_replacements = muts.select { |m| m.diff.include?("nil") }

        expect(nil_replacements.length).to eq(1)
      end
    end

    context "else branch removal" do
      it "removes else branch when present" do
        muts = mutations_for("simple_case")
        else_removals = muts.select { |m| m.diff.include?("else") && m.diff.include?("-") }

        expect(else_removals.length).to eq(1)
      end

      it "generates no else removal when else is absent" do
        muts = mutations_for("case_without_else")
        else_removals = muts.select { |m| m.diff.include?("else") }

        expect(else_removals).to be_empty
      end

      it "removes the else keyword together with its body" do
        muts = mutations_for("simple_case")
        else_removal = muts.find { |m| m.diff.match?(/^-\s+else/) }

        expect(else_removal).not_to be_nil
        # The whole else clause (keyword + body) must be gone, not just the
        # `else` keyword: `"other"` must not survive in the simple_case body.
        case_body = else_removal.mutated_source[/def simple_case\(x\)\n(.*?)\n  end/m, 1]
        expect(case_body).not_to match(/^\s*"other"/)
        expect(case_body).not_to include("else")
      end
    end

    context "with an empty else body" do
      it "does not emit an else-removal mutation when the else body is empty" do
        muts = mutations_from_source(
          "empty_else",
          "class C\n  def empty_else(x)\n    case x\n    when 1\n      1\n    else\n    end\n  end\nend\n"
        )

        expect(muts.length).to eq(1)
        expect(muts.first.diff).not_to match(/^-\s+else/)
      end
    end

    context "when condition removal" do
      # A whole-clause removal replaces the arm with blank, so only a condition
      # removal leaves a `when` on the added side of the diff.
      def condition_removals(muts)
        muts.select { |m| m.diff.match?(/^\+\s+when\s/) }
      end

      it "drops each condition of a two-condition arm in turn" do
        muts = condition_removals(mutations_for("two_conditions"))

        expect(muts.map { |m| m.mutated_slice.strip }).to contain_exactly("when 1", "when 2")
      end

      it "drops each condition of a three-condition arm in turn" do
        muts = condition_removals(mutations_for("three_conditions"))

        expect(muts.map { |m| m.mutated_slice.strip }).to contain_exactly(
          "when :b, :c", "when :a, :c", "when :a, :b"
        )
      end

      # A one-line `then` arm keeps `when` on the body line too, so this one
      # asserts against every mutation of the arm rather than filtering.
      it "keeps the then keyword when shortening the list" do
        muts = mutations_for("conditions_with_then")

        expect(muts.map { |m| m.mutated_slice.strip }).to include(
          "when 1 then \"low\"", "when 2 then \"low\""
        )
      end

      it "drops a splat condition like any other" do
        muts = condition_removals(mutations_for("conditions_with_splat"))

        expect(muts.map { |m| m.mutated_slice.strip }).to contain_exactly("when 1", "when *rest")
      end

      # Scanning must continue past single-condition arms, not stop at the
      # first one.
      it "shortens a multi-condition arm that follows a single-condition arm" do
        muts = condition_removals(mutations_for("single_condition_arm_first"))

        expect(muts.map { |m| m.mutated_slice.strip }).to contain_exactly("when 2", "when 3")
      end

      it "emits nothing for a single-condition arm" do
        muts = condition_removals(mutations_for("single_when"))

        expect(muts).to be_empty
      end

      it "produces valid Ruby when the conditions span several lines" do
        muts = condition_removals(mutations_for("conditions_across_lines"))

        expect(muts.length).to eq(2)
        muts.each do |mutation|
          expect(Prism.parse(mutation.mutated_source).errors).to be_empty
        end
      end
    end

    context "empty when body raise insertion" do
      def raise_insertions(muts)
        muts.select { |m| m.diff.match?(/^\+\s+raise$/) }
      end

      it "inserts a raise into an empty when body" do
        muts = mutations_for("case_with_empty_when")

        expect(raise_insertions(muts).map(&:mutated_source)).to match(
          [a_string_including("when 1\n      raise\n")]
        )
      end

      it "inserts after the then keyword when the empty arm uses one" do
        muts = mutations_for("empty_when_with_then")

        expect(raise_insertions(muts).map(&:mutated_source)).to match(
          [a_string_including("when 1 then\n      raise\n")]
        )
      end

      it "inserts after the last condition of a multi-condition arm" do
        muts = mutations_for("empty_when_multiple_conditions")

        expect(raise_insertions(muts).map(&:mutated_source)).to match(
          [a_string_including("when 1, 2\n      raise\n")]
        )
      end

      # Branch removal needs two or more arms, so on a lone empty arm the raise
      # is the only thing proving the arm was selected.
      it "inserts into a lone empty when arm" do
        muts = mutations_for("only_empty_when")

        expect(raise_insertions(muts).length).to eq(1)
      end

      # Scanning must continue past arms that have a body, not stop at the
      # first one.
      it "inserts into an empty arm that follows an arm with a body" do
        muts = mutations_for("empty_when_after_body")

        expect(raise_insertions(muts).map(&:mutated_source)).to match(
          [a_string_including("when 2\n      raise\n")]
        )
      end

      it "leaves arms that already have a body alone" do
        muts = mutations_for("simple_case")

        expect(raise_insertions(muts)).to be_empty
      end

      it "indents the raise to match the arm it belongs to" do
        muts = mutations_from_source(
          "nested_empty",
          "class C\n  def nested_empty(x)\n    case x\n    when 1\n      case x\n      " \
          "when 2\n      end\n    end\n  end\nend\n"
        )

        expect(raise_insertions(muts).map(&:mutated_source)).to match(
          [a_string_including("      when 2\n        raise\n")]
        )
      end
    end

    it "descends into a case nested inside a when body" do
      muts = mutations_from_source(
        "nested",
        "class C\n  def nested(x)\n    case x\n    when 1\n      case x\n      " \
        "when 2 then 3\n      when 4 then 5\n      end\n    when 6\n      7\n    end\n  end\nend\n"
      )

      # The inner case's when-branches are only reachable via visitor recursion.
      expect(muts.map(&:mutated_source)).to include(
        a_string_matching(/when 2 then nil/),
        a_string_matching(/when 4 then nil/)
      )
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
      muts = mutations_for("simple_case")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("case_when")
      end
    end
  end
end
