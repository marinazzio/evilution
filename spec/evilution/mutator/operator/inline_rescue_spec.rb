# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/inline_rescue"

RSpec.describe Evilution::Mutator::Operator::InlineRescue do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/inline_rescue.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:simple_subject) { subjects.find { |s| s.name.include?("simple_inline_rescue") } }
  let(:nil_fallback_subject) { subjects.find { |s| s.name.include?("inline_rescue_with_nil_fallback") } }
  let(:assignment_subject) { subjects.find { |s| s.name.include?("inline_rescue_in_assignment") } }
  let(:no_rescue_subject) { subjects.find { |s| s.name.include?("no_rescue") } }
  let(:multiple_subject) { subjects.find { |s| s.name.include?("multiple_inline_rescues") } }

  describe "#call" do
    it "generates two mutations for a simple inline rescue (remove rescue, nil fallback)" do
      mutations = described_class.new.call(simple_subject)

      expect(mutations.length).to eq(2)
    end

    it "generates no mutations when there is no rescue" do
      mutations = described_class.new.call(no_rescue_subject)

      expect(mutations).to be_empty
    end

    it "removes the rescue clause, keeping only the expression" do
      mutations = described_class.new.call(simple_subject)
      removal = mutations.find { |m| m.diff.include?("+ ") && !m.diff.match?(/\+.*rescue/) }

      expect(removal).not_to be_nil
      expect(removal.diff).to include("- ", "dangerous_call rescue fallback_value")
      result = Prism.parse(removal.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{removal.mutated_source}"
    end

    it "replaces the fallback with nil" do
      mutations = described_class.new.call(simple_subject)
      nil_mutation = mutations.find { |m| m.diff.include?("nil") }

      expect(nil_mutation).not_to be_nil
      expect(nil_mutation.mutated_source).to include("rescue nil")
      result = Prism.parse(nil_mutation.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{nil_mutation.mutated_source}"
    end

    it "skips nil fallback replacement when fallback is already nil" do
      mutations = described_class.new.call(nil_fallback_subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).not_to match(/\+.*rescue/)
    end

    it "handles inline rescue inside assignment" do
      mutations = described_class.new.call(assignment_subject)

      expect(mutations.length).to eq(2)
      mutations.each do |mutation|
        result = Prism.parse(mutation.mutated_source)
        expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
      end
    end

    it "generates mutations for each inline rescue in a method" do
      mutations = described_class.new.call(multiple_subject)

      expect(mutations.length).to eq(4)
    end

    it "produces valid Ruby for all mutations" do
      [simple_subject, assignment_subject, multiple_subject].each do |subj|
        mutations = described_class.new.call(subj)
        mutations.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
        end
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(simple_subject)

      expect(mutations.first.operator_name).to eq("inline_rescue")
    end
  end
end
