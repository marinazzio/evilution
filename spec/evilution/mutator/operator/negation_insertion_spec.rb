# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/negation_insertion"

RSpec.describe Evilution::Mutator::Operator::NegationInsertion do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/negation.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:empty_subject) { subjects.find { |s| s.name.include?("check_empty") } }
  let(:nil_subject) { subjects.find { |s| s.name.include?("check_nil") } }
  let(:non_predicate_subject) { subjects.find { |s| s.name.include?("check_non_predicate") } }

  describe "#call" do
    it "inserts ! before a predicate call like .empty?" do
      mutations = described_class.new.call(empty_subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.mutated_source).to include("!list.empty?")
    end

    it "inserts ! before a predicate call like .nil?" do
      mutations = described_class.new.call(nil_subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.mutated_source).to include("!value.nil?")
    end

    it "does not mutate non-predicate method calls" do
      mutations = described_class.new.call(non_predicate_subject)

      expect(mutations).to be_empty
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

    it "sets correct operator_name" do
      mutations = described_class.new.call(empty_subject)

      expect(mutations.first.operator_name).to eq("negation_insertion")
    end
  end
end
