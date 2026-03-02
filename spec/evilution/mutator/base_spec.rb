# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Base do
  describe ".operator_name" do
    it "converts class name to snake_case" do
      stub_const("Evilution::Mutator::Operator::ComparisonReplacement", Class.new(described_class))

      expect(Evilution::Mutator::Operator::ComparisonReplacement.operator_name).to eq("comparison_replacement")
    end
  end

  describe "#call" do
    it "returns an empty array when no mutations are generated" do
      subject_obj = double("Subject",
                           file_path: File.expand_path("../../support/fixtures/simple_class.rb", __dir__),
                           node: Prism.parse("def foo\n  42\nend").value.statements.body.first)

      base = described_class.new
      result = base.call(subject_obj)

      expect(result).to eq([])
    end
  end
end
