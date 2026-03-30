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

    it "skips mutations when filter matches the node" do
      operator_class = Class.new(described_class) do
        def visit_call_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: node.location.end_offset - node.location.start_offset,
            replacement: "nil",
            node: node
          )
        end
      end

      fixture_path = File.expand_path("../../support/fixtures/simple_class.rb", __dir__)
      code = "log()"
      tree = Prism.parse(code).value
      node = tree.statements.body.first
      subject_obj = double("Subject", name: "Test#m", file_path: fixture_path, node: node)

      filter = Evilution::AST::Pattern::Filter.new(["call{name=log}"])
      operator = operator_class.new
      result = operator.call(subject_obj, filter: filter)

      expect(result).to be_empty
      expect(filter.skipped_count).to eq(1)
    end

    it "allows mutations when filter does not match" do
      operator_class = Class.new(described_class) do
        def visit_call_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: node.location.end_offset - node.location.start_offset,
            replacement: "nil",
            node: node
          )
        end
      end

      fixture_path = File.expand_path("../../support/fixtures/simple_class.rb", __dir__)
      code = "info()"
      tree = Prism.parse(code).value
      node = tree.statements.body.first
      subject_obj = double("Subject", name: "Test#m", file_path: fixture_path, node: node)

      filter = Evilution::AST::Pattern::Filter.new(["call{name=log}"])
      operator = operator_class.new
      result = operator.call(subject_obj, filter: filter)

      expect(result.length).to eq(1)
      expect(filter.skipped_count).to eq(0)
    end
  end
end
