# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/next_statement"

RSpec.describe Evilution::Mutator::Operator::NextStatement do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/next_statement.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:no_value_subject) { subjects.find { |s| s.name.include?("next_without_value") } }
  let(:with_value_subject) { subjects.find { |s| s.name.include?("next_with_value") } }
  let(:simple_subject) { subjects.find { |s| s.name.include?("simple_next") } }
  let(:no_next_subject) { subjects.find { |s| s.name.include?("no_next") } }
  let(:multiple_subject) { subjects.find { |s| s.name.include?("multiple_nexts") } }

  describe "#call" do
    it "generates two mutations for next without value (remove, swap to break)" do
      mutations = described_class.new.call(no_value_subject)

      expect(mutations.length).to eq(2)
    end

    it "generates three mutations for next with value (remove, nil value, swap to break)" do
      mutations = described_class.new.call(with_value_subject)

      expect(mutations.length).to eq(3)
    end

    it "generates no mutations when there is no next" do
      mutations = described_class.new.call(no_next_subject)

      expect(mutations).to be_empty
    end

    it "removes next statement" do
      mutations = described_class.new.call(no_value_subject)
      removal = mutations.find { |m| m.diff.include?("+") && !m.diff.match?(/\+.*(?:next|break)/) }

      expect(removal).not_to be_nil
      result = Prism.parse(removal.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{removal.mutated_source}"
    end

    it "swaps next with break" do
      mutations = described_class.new.call(no_value_subject)
      swap = mutations.find { |m| m.diff.match?(/\+.*break/) }

      expect(swap).not_to be_nil
      expect(swap.diff).to include("- ", "next")
      expect(swap.diff).to include("+ ", "break")
      result = Prism.parse(swap.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{swap.mutated_source}"
    end

    it "replaces next value with nil" do
      mutations = described_class.new.call(with_value_subject)
      nil_mutation = mutations.find { |m| m.diff.match?(/\+.*next nil/) }

      expect(nil_mutation).not_to be_nil
      result = Prism.parse(nil_mutation.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{nil_mutation.mutated_source}"
    end

    it "generates mutations for each next in a method" do
      mutations = described_class.new.call(multiple_subject)

      # First next: no value -> 2 mutations (remove, swap)
      # Second next: with value -> 3 mutations (remove, nil value, swap)
      expect(mutations.length).to eq(5)
    end

    it "produces valid Ruby for all mutations" do
      [no_value_subject, with_value_subject, simple_subject, multiple_subject].each do |subj|
        mutations = described_class.new.call(subj)
        mutations.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
        end
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(no_value_subject)

      expect(mutations.first.operator_name).to eq("next_statement")
    end
  end
end
