# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/ensure_removal"

RSpec.describe Evilution::Mutator::Operator::EnsureRemoval do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/ensure_removal.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:simple_subject) { subjects.find { |s| s.name.include?("simple_ensure") } }
  let(:multi_body_subject) { subjects.find { |s| s.name.include?("ensure_with_multi_line_body") } }
  let(:rescue_subject) { subjects.find { |s| s.name.include?("ensure_with_rescue") } }
  let(:no_ensure_subject) { subjects.find { |s| s.name.include?("no_ensure") } }
  let(:empty_body_subject) { subjects.find { |s| s.name.include?("ensure_without_body") } }

  describe "#call" do
    it "generates one mutation for a simple ensure clause" do
      mutations = described_class.new.call(simple_subject)

      expect(mutations.length).to eq(1)
    end

    it "generates no mutations when there is no ensure" do
      mutations = described_class.new.call(no_ensure_subject)

      expect(mutations).to be_empty
    end

    it "removes the ensure clause entirely" do
      mutations = described_class.new.call(simple_subject)
      mutation = mutations.first

      expect(mutation.diff).to include("- ", "ensure")
      expect(mutation.diff).to include("- ", "cleanup")
      result = Prism.parse(mutation.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
    end

    it "removes multi-line ensure body" do
      mutations = described_class.new.call(multi_body_subject)
      mutation = mutations.first

      expect(mutation.diff).to include("- ", "close_connection")
      expect(mutation.diff).to include("- ", "release_lock")
      result = Prism.parse(mutation.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
    end

    it "removes ensure while preserving rescue clause" do
      mutations = described_class.new.call(rescue_subject)
      mutation = mutations.first

      expect(mutation.mutated_source).to include("rescue StandardError")
      expect(mutation.mutated_source).to include("handle_error")
      expect(mutation.diff).to include("- ", "ensure")
      expect(mutation.diff).to include("- ", "cleanup")
      result = Prism.parse(mutation.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
    end

    it "removes empty ensure clause" do
      mutations = described_class.new.call(empty_body_subject)
      mutation = mutations.first

      expect(mutation).not_to be_nil
      expect(mutation.diff).to include("- ", "ensure")
      result = Prism.parse(mutation.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
    end

    it "produces valid Ruby for all mutations" do
      [simple_subject, multi_body_subject, rescue_subject, empty_body_subject].each do |subj|
        mutations = described_class.new.call(subj)
        mutations.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
        end
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(simple_subject)

      expect(mutations.first.operator_name).to eq("ensure_removal")
    end
  end
end
