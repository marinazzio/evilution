# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/instance_variable_write"

RSpec.describe Evilution::Mutator::Operator::InstanceVariableWrite do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/instance_variable_write.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:multi_subject) { subjects.find { |s| s.name.include?("with_ivars") } }
  let(:single_subject) { subjects.find { |s| s.name.include?("single_ivar") } }
  let(:no_ivar_subject) { subjects.find { |s| s.name.include?("no_ivars") } }

  describe "#call" do
    it "generates two mutations per instance variable write" do
      mutations = described_class.new.call(multi_subject)

      expect(mutations.length).to eq(4)
    end

    it "generates two mutations for a single ivar write" do
      mutations = described_class.new.call(single_subject)

      expect(mutations.length).to eq(2)
    end

    it "generates no mutations when there are no ivar writes" do
      mutations = described_class.new.call(no_ivar_subject)

      expect(mutations).to be_empty
    end

    it "generates a removal mutation that keeps only the value" do
      mutations = described_class.new.call(single_subject)
      removal = mutations.find { |m| m.diff.include?("compute") && !m.diff.include?("nil") }

      expect(removal).not_to be_nil
      expect(removal.diff).to include("- ", "@result = compute")
      expect(removal.diff).to include("+ ", "compute")
    end

    it "generates a nil replacement mutation" do
      mutations = described_class.new.call(single_subject)
      nil_mutation = mutations.find { |m| m.diff.include?("nil") }

      expect(nil_mutation).not_to be_nil
      expect(nil_mutation.diff).to include("- ", "@result = compute")
      expect(nil_mutation.diff).to include("+ ", "@result = nil")
    end

    it "replaces exactly the value span when substituting nil" do
      # The nil substitution must use the value's own length: a wrong length
      # would overrun the value and corrupt the surrounding source (e.g.
      # "@result = nillt" or a truncated body).
      mutations = described_class.new.call(single_subject)
      nil_mutation = mutations.find { |m| m.mutated_source.include?("= nil") }

      expect(nil_mutation).not_to be_nil
      expect(nil_mutation.mutated_source).to include("    @result = nil\n    @result\n  end")
    end

    it "produces valid Ruby for all mutations" do
      mutations = described_class.new.call(multi_subject)
      mutations.each do |mutation|
        result = Prism.parse(mutation.mutated_source)
        expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
      end
    end

    it "recurses into the value to mutate a nested instance variable write" do
      # `@a = (@b = 1)`: the outer write yields 2 mutations and the nested
      # `@b = 1` write yields 2 more — only reached when the visitor recurses
      # into the assigned value expression.
      nested_subject = subjects.find { |s| s.name.include?("nested_ivar") }
      mutations = described_class.new.call(nested_subject)

      expect(mutations.length).to eq(4)
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(multi_subject)

      expect(mutations.first.operator_name).to eq("instance_variable_write")
    end
  end
end
