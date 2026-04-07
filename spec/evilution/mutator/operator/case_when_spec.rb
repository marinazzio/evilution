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
