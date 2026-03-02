# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/statement_deletion"

RSpec.describe Evilution::Mutator::Operator::StatementDeletion do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/statement_deletion.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:multi_subject) { subjects.find { |s| s.name.include?("multi_statement") } }
  let(:single_subject) { subjects.find { |s| s.name.include?("single_statement") } }

  describe "#call" do
    it "generates one mutation per statement for a 3-statement method" do
      mutations = described_class.new.call(multi_subject)

      expect(mutations.length).to eq(3)
    end

    it "generates no mutations for a 1-statement method" do
      mutations = described_class.new.call(single_subject)

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
      mutations = described_class.new.call(multi_subject)

      expect(mutations.first.operator_name).to eq("statement_deletion")
    end
  end
end
