# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/conditional_negation"

RSpec.describe Evilution::Mutator::Operator::ConditionalNegation do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/conditional.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:if_subject) { subjects.find { |s| s.name.include?("check_positive") } }
  let(:unless_subject) { subjects.find { |s| s.name.include?("check_negative") } }

  describe "#call" do
    it "replaces if condition with true and false" do
      mutations = described_class.new.call(if_subject)

      expect(mutations.length).to eq(2)
      expect(mutations.map(&:mutated_source)).to include(
        a_string_matching(/if true/),
        a_string_matching(/if false/)
      )
    end

    it "replaces unless condition with true and false" do
      mutations = described_class.new.call(unless_subject)

      expect(mutations.length).to eq(2)
      expect(mutations.map(&:mutated_source)).to include(
        a_string_matching(/unless true/),
        a_string_matching(/unless false/)
      )
    end

    it "produces valid Ruby for all mutations" do
      subjects.each do |subject|
        mutations = described_class.new.call(subject)
        mutations.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
        end
      end
    end

    it "recurses into an if body to mutate a nested if predicate" do
      # The outer if produces 2 mutations; the nested if produces 2 more,
      # but only when the visitor recurses into the outer if's body.
      nested_subject = subjects.find { |s| s.name.include?("nested_if") }
      mutations = described_class.new.call(nested_subject)

      expect(mutations.length).to eq(4)
    end

    it "recurses into an unless body to mutate a nested unless predicate" do
      # The outer unless produces 2 mutations; the nested unless produces 2
      # more, but only when the visitor recurses into the outer unless body.
      nested_subject = subjects.find { |s| s.name.include?("nested_unless") }
      mutations = described_class.new.call(nested_subject)

      expect(mutations.length).to eq(4)
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(if_subject)

      expect(mutations.first.operator_name).to eq("conditional_negation")
    end
  end
end
