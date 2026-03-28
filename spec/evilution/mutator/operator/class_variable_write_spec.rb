# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/class_variable_write"

RSpec.describe Evilution::Mutator::Operator::ClassVariableWrite do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/class_variable_write.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:multi_subject) { subjects.find { |s| s.name.include?("with_cvars") } }
  let(:single_subject) { subjects.find { |s| s.name.include?("single_cvar") } }
  let(:no_cvar_subject) { subjects.find { |s| s.name.include?("no_cvars") } }

  describe "#call" do
    it "generates two mutations per class variable write" do
      mutations = described_class.new.call(multi_subject)

      expect(mutations.length).to eq(4)
    end

    it "generates two mutations for a single cvar write" do
      mutations = described_class.new.call(single_subject)

      expect(mutations.length).to eq(2)
    end

    it "generates no mutations when there are no cvar writes" do
      mutations = described_class.new.call(no_cvar_subject)

      expect(mutations).to be_empty
    end

    it "generates a removal mutation that keeps only the value" do
      mutations = described_class.new.call(single_subject)
      removal = mutations.find { |m| m.diff.include?("compute") && !m.diff.include?("nil") }

      expect(removal).not_to be_nil
      expect(removal.diff).to include("- ", "@@total = compute")
      expect(removal.diff).to include("+ ", "compute")
    end

    it "generates a nil replacement mutation" do
      mutations = described_class.new.call(single_subject)
      nil_mutation = mutations.find { |m| m.diff.include?("nil") }

      expect(nil_mutation).not_to be_nil
      expect(nil_mutation.diff).to include("- ", "@@total = compute")
      expect(nil_mutation.diff).to include("+ ", "@@total = nil")
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

      expect(mutations.first.operator_name).to eq("class_variable_write")
    end
  end
end
