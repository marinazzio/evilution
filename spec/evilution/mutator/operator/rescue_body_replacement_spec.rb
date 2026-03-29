# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/rescue_body_replacement"

RSpec.describe Evilution::Mutator::Operator::RescueBodyReplacement do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/rescue_body_replacement.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:single_subject) { subjects.find { |s| s.name.include?("single_rescue") } }
  let(:multi_body_subject) { subjects.find { |s| s.name.include?("rescue_with_multi_line_body") } }
  let(:multi_rescue_subject) { subjects.find { |s| s.name.include?("multiple_rescues") } }
  let(:no_rescue_subject) { subjects.find { |s| s.name.include?("no_rescue") } }
  let(:raise_subject) { subjects.find { |s| s.name.include?("rescue_with_raise") } }
  let(:empty_subject) { subjects.find { |s| s.name.include?("empty_rescue") } }

  describe "#call" do
    it "generates two mutations for a single rescue clause (nil and raise)" do
      mutations = described_class.new.call(single_subject)

      expect(mutations.length).to eq(2)
    end

    it "generates two mutations per rescue clause for multiple rescues" do
      mutations = described_class.new.call(multi_rescue_subject)

      expect(mutations.length).to eq(4)
    end

    it "generates no mutations when there is no rescue" do
      mutations = described_class.new.call(no_rescue_subject)

      expect(mutations).to be_empty
    end

    it "replaces rescue body with nil" do
      mutations = described_class.new.call(single_subject)
      nil_mutation = mutations.find { |m| m.mutated_source.include?("nil") }

      expect(nil_mutation).not_to be_nil
      expect(nil_mutation.diff).to include("- ", "handle_error")
      expect(nil_mutation.diff).to include("+ ", "nil")
      result = Prism.parse(nil_mutation.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{nil_mutation.mutated_source}"
    end

    it "replaces rescue body with raise" do
      mutations = described_class.new.call(single_subject)
      raise_mutation = mutations.find { |m| m.diff.include?("raise") }

      expect(raise_mutation).not_to be_nil
      expect(raise_mutation.diff).to include("- ", "handle_error")
      expect(raise_mutation.diff).to include("+ ", "raise")
      result = Prism.parse(raise_mutation.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{raise_mutation.mutated_source}"
    end

    it "replaces multi-line rescue body with nil" do
      mutations = described_class.new.call(multi_body_subject)
      nil_mutation = mutations.find { |m| m.mutated_source.include?("nil") }

      expect(nil_mutation).not_to be_nil
      expect(nil_mutation.diff).to include("- ", "log(e)")
      expect(nil_mutation.diff).to include("- ", "fallback")
      expect(nil_mutation.diff).to include("+ ", "nil")
      result = Prism.parse(nil_mutation.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{nil_mutation.mutated_source}"
    end

    it "skips raise replacement when body is already a bare raise" do
      mutations = described_class.new.call(raise_subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to include("nil")
    end

    it "generates only raise mutation for empty rescue body" do
      mutations = described_class.new.call(empty_subject)

      expect(mutations.length).to eq(1)
      raise_mutation = mutations.first
      expect(raise_mutation.mutated_source).to include("raise")
      result = Prism.parse(raise_mutation.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{raise_mutation.mutated_source}"
    end

    it "produces valid Ruby for all mutations" do
      [single_subject, multi_body_subject, multi_rescue_subject].each do |subj|
        mutations = described_class.new.call(subj)
        mutations.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
        end
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(single_subject)

      expect(mutations.first.operator_name).to eq("rescue_body_replacement")
    end
  end
end
