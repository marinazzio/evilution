# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/rescue_removal"

RSpec.describe Evilution::Mutator::Operator::RescueRemoval do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/rescue_removal.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:single_subject) { subjects.find { |s| s.name.include?("single_rescue") } }
  let(:multi_subject) { subjects.find { |s| s.name.include?("multiple_rescues") } }
  let(:no_rescue_subject) { subjects.find { |s| s.name.include?("no_rescue") } }
  let(:body_subject) { subjects.find { |s| s.name.include?("rescue_with_body") } }

  describe "#call" do
    it "generates one mutation for a single rescue clause" do
      mutations = described_class.new.call(single_subject)

      expect(mutations.length).to eq(1)
    end

    it "generates one mutation per rescue clause for multiple rescues" do
      mutations = described_class.new.call(multi_subject)

      expect(mutations.length).to eq(2)
    end

    it "generates no mutations when there is no rescue" do
      mutations = described_class.new.call(no_rescue_subject)

      expect(mutations).to be_empty
    end

    it "removes the single rescue clause entirely" do
      mutations = described_class.new.call(single_subject)
      mutation = mutations.first

      expect(mutation.diff).to include("- ", "rescue ArgumentError")
      expect(mutation.diff).to include("- ", "handle_error")
      result = Prism.parse(mutation.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
    end

    it "removes the first rescue clause from multiple rescues" do
      mutations = described_class.new.call(multi_subject)
      first_removal = mutations.find { |m| m.diff.include?("ArgumentError") }

      expect(first_removal).not_to be_nil
      expect(first_removal.diff).to include("rescue ArgumentError")
      expect(first_removal.diff).not_to include("RuntimeError")
      result = Prism.parse(first_removal.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{first_removal.mutated_source}"
    end

    it "removes the second rescue clause from multiple rescues" do
      mutations = described_class.new.call(multi_subject)
      second_removal = mutations.find { |m| m.diff.include?("RuntimeError") }

      expect(second_removal).not_to be_nil
      expect(second_removal.diff).to include("rescue RuntimeError")
      expect(second_removal.diff).not_to include("ArgumentError")
      result = Prism.parse(second_removal.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{second_removal.mutated_source}"
    end

    it "produces valid Ruby for all mutations" do
      mutations = described_class.new.call(body_subject)
      mutations.each do |mutation|
        result = Prism.parse(mutation.mutated_source)
        expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(single_subject)

      expect(mutations.first.operator_name).to eq("rescue_removal")
    end
  end
end
