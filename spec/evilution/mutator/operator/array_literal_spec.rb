# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/array_literal"

RSpec.describe Evilution::Mutator::Operator::ArrayLiteral do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/array_literal.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:non_empty_subject) { subjects.find { |s| s.name.include?("returns_non_empty_array") } }
  let(:empty_subject) { subjects.find { |s| s.name.include?("returns_empty_array") } }

  describe "#call" do
    it "replaces [1, 2, 3] with []" do
      mutations = described_class.new.call(non_empty_subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.mutated_source).to match(/\[\]/)
    end

    it "does not mutate empty arrays" do
      mutations = described_class.new.call(empty_subject)

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
      mutations = described_class.new.call(non_empty_subject)

      expect(mutations.first.operator_name).to eq("array_literal")
    end
  end
end
