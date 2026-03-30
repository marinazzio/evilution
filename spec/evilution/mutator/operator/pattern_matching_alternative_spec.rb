# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/pattern_matching_alternative"

RSpec.describe Evilution::Mutator::Operator::PatternMatchingAlternative do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/pattern_matching_alternative.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  def mutations_for(method_name)
    subject_obj = subjects.find { |s| s.name.include?(method_name) }
    raise "Subject not found: #{method_name}" unless subject_obj

    described_class.new.call(subject_obj)
  end

  describe "#call" do
    it "removes left alternative" do
      mutations = mutations_for("two_alternatives")

      removed_left = mutations.select { |m| m.mutated_source.include?("in Float\n") }
      expect(removed_left).not_to be_empty
    end

    it "removes right alternative" do
      mutations = mutations_for("two_alternatives")

      removed_right = mutations.select { |m| m.mutated_source.include?("in Integer\n") }
      expect(removed_right).not_to be_empty
    end

    it "swaps alternative order" do
      mutations = mutations_for("two_alternatives")

      swapped = mutations.select { |m| m.mutated_source.include?("in Float | Integer") }
      expect(swapped).not_to be_empty
    end

    it "produces 3 mutations for a two-way alternation" do
      mutations = mutations_for("two_alternatives")

      expect(mutations.length).to eq(3)
    end

    it "produces 6 mutations for a three-way alternation" do
      mutations = mutations_for("three_alternatives")

      expect(mutations.length).to eq(6)
    end

    it "removes each branch of three-way alternation at outer level" do
      mutations = mutations_for("three_alternatives")

      removed_right = mutations.select { |m| m.mutated_source.include?("in :foo | :bar\n") }
      removed_left = mutations.select { |m| m.mutated_source.include?("in :baz\n") }
      expect(removed_right).not_to be_empty
      expect(removed_left).not_to be_empty
    end

    it "produces no mutations for patterns without alternatives" do
      mutations = mutations_for("no_alternatives")

      expect(mutations).to be_empty
    end

    it "handles complex pattern alternatives" do
      mutations = mutations_for("complex_alternatives")

      expect(mutations.length).to eq(3)
    end

    it "produces valid Ruby for all mutations" do
      subjects.each do |subject_obj|
        mutations = described_class.new.call(subject_obj)
        mutations.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty,
                                   "Invalid Ruby from #{subject_obj.name}: #{mutation.mutated_source}"
        end
      end
    end

    it "sets correct operator_name" do
      mutations = mutations_for("two_alternatives")

      expect(mutations.first.operator_name).to eq("pattern_matching_alternative")
    end
  end
end
