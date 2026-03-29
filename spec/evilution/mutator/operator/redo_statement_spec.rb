# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/redo_statement"

RSpec.describe Evilution::Mutator::Operator::RedoStatement do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/redo_statement.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:simple_subject) { subjects.find { |s| s.name.include?("simple_redo") } }
  let(:loop_subject) { subjects.find { |s| s.name.include?("redo_in_loop") } }
  let(:no_redo_subject) { subjects.find { |s| s.name.include?("no_redo") } }
  let(:multiple_subject) { subjects.find { |s| s.name.include?("multiple_redos") } }

  describe "#call" do
    it "generates one mutation for a single redo" do
      mutations = described_class.new.call(simple_subject)

      expect(mutations.length).to eq(1)
    end

    it "generates no mutations when there is no redo" do
      mutations = described_class.new.call(no_redo_subject)

      expect(mutations).to be_empty
    end

    it "removes the redo statement" do
      mutations = described_class.new.call(simple_subject)
      mutation = mutations.first

      expect(mutation.diff).to include("- ", "redo")
      expect(mutation.diff).to include("+ ", "nil")
      result = Prism.parse(mutation.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
    end

    it "removes redo in a loop" do
      mutations = described_class.new.call(loop_subject)
      mutation = mutations.first

      expect(mutation).not_to be_nil
      result = Prism.parse(mutation.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
    end

    it "generates one mutation per redo" do
      mutations = described_class.new.call(multiple_subject)

      expect(mutations.length).to eq(2)
    end

    it "produces valid Ruby for all mutations" do
      [simple_subject, loop_subject, multiple_subject].each do |subj|
        mutations = described_class.new.call(subj)
        mutations.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
        end
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(simple_subject)

      expect(mutations.first.operator_name).to eq("redo_statement")
    end
  end
end
