# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/local_variable_assignment"

RSpec.describe Evilution::Mutator::Operator::LocalVariableAssignment do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/local_variable_assignment.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:multi_subject) { subjects.find { |s| s.name.include?("with_assignments") } }
  let(:single_subject) { subjects.find { |s| s.name.include?("single_assignment") } }
  let(:no_assign_subject) { subjects.find { |s| s.name.include?("no_assignments") } }

  describe "#call" do
    it "generates one mutation per local variable assignment" do
      mutations = described_class.new.call(multi_subject)

      expect(mutations.length).to eq(2)
    end

    it "generates a mutation for a single assignment" do
      mutations = described_class.new.call(single_subject)

      expect(mutations.length).to eq(1)
    end

    it "generates no mutations when there are no assignments" do
      mutations = described_class.new.call(no_assign_subject)

      expect(mutations).to be_empty
    end

    it "replaces the assignment with just the value expression" do
      mutations = described_class.new.call(multi_subject)
      first_mutation = mutations.first

      expect(first_mutation.diff).to include("- ", "x = 42")
      expect(first_mutation.diff).to include("+ ", "42")
    end

    it "produces valid Ruby for all mutations" do
      mutations = described_class.new.call(multi_subject)
      mutations.each do |mutation|
        result = Prism.parse(mutation.mutated_source)
        expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(multi_subject)

      expect(mutations.first.operator_name).to eq("local_variable_assignment")
    end
  end
end
