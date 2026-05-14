# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/last_expression_removal"

RSpec.describe Evilution::Mutator::Operator::LastExpressionRemoval do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/last_expression_removal.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  def subject_named(name)
    subjects.find { |s| s.name.include?(name) }
  end

  describe "#call" do
    # mutation.diff returns only added/removed lines, so assertions are scoped
    # to the operator's actual change — not whatever the full fixture file
    # happens to contain.
    it "generates a mutation removing a trailing `true` literal" do
      mutations = described_class.new.call(subject_named("predicate_true"))

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to match(/^-\s*true\s*$/)
    end

    it "generates a mutation removing a trailing `false` literal" do
      mutations = described_class.new.call(subject_named("predicate_false"))

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to match(/^-\s*false\s*$/)
    end

    it "generates a mutation removing a trailing `nil` literal" do
      mutations = described_class.new.call(subject_named("trailing_nil"))

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to match(/^-\s*nil\s*$/)
    end

    it "generates a mutation removing a trailing integer literal" do
      mutations = described_class.new.call(subject_named("trailing_integer"))

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to match(/^-\s*42\s*$/)
    end

    it "generates a mutation removing a trailing symbol literal" do
      mutations = described_class.new.call(subject_named("trailing_symbol"))

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to match(/^-\s*:ok\s*$/)
    end

    it "fires on a single-statement method body that is a literal" do
      # statement_deletion does not handle length-1 bodies; this is the gap
      # the operator targets (predicates whose entire body is a literal).
      mutations = described_class.new.call(subject_named("single_literal"))

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to match(/^-\s*true\s*$/)
    end

    it "skips methods whose last statement is not a literal" do
      mutations = described_class.new.call(subject_named("no_trailing_literal"))

      expect(mutations).to be_empty
    end

    it "skips empty methods" do
      mutations = described_class.new.call(subject_named("empty"))

      expect(mutations).to be_empty
    end

    it "skips methods whose last statement is a method call (not a literal)" do
      mutations = described_class.new.call(subject_named("trailing_call"))

      expect(mutations).to be_empty
    end

    it "produces parseable Ruby" do
      subjects.each do |s|
        described_class.new.call(s).each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
        end
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(subject_named("predicate_true"))

      expect(mutations.first.operator_name).to eq("last_expression_removal")
    end
  end
end
