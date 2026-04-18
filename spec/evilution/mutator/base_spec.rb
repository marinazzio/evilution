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

    it "populates original_slice and mutated_slice from affected line range" do
      operator_class = Class.new(described_class) do
        def visit_integer_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: node.location.end_offset - node.location.start_offset,
            replacement: "0",
            node: node
          )
        end
      end

      fixture_path = File.expand_path("../../support/fixtures/simple_class.rb", __dir__)
      file_source = File.read(fixture_path)
      tree = Prism.parse(file_source).value
      subject_obj = double("Subject", name: "User#adult?", file_path: fixture_path, node: tree)

      result = operator_class.new.call(subject_obj)
      age_check = result.find { |m| m.line == 10 }

      expect(age_check).not_to be_nil
      expect(age_check.original_slice).to eq("    @age >= 18\n")
      expect(age_check.mutated_slice).to eq("    @age >= 0\n")
    end

    it "marks mutation parse_status :unparseable when Prism cannot parse mutated source" do
      operator_class = Class.new(described_class) do
        def visit_call_node(node)
          add_mutation(
            offset: node.location.end_offset - 1,
            length: 1,
            replacement: "",
            node: node
          )
        end
      end

      code = "config[:font_size]\n"
      tree = Prism.parse(code).value
      node = tree.statements.body.first
      subject_obj = double("Subject", name: "Test#m", file_path: "x.rb", node: node)

      operator = operator_class.new
      operator.instance_variable_set(:@file_source, code)
      operator.instance_variable_set(:@filter, nil)
      operator.instance_variable_set(:@subject, subject_obj)
      operator.send(:add_mutation, offset: 17, length: 1, replacement: "", node: node)

      mutation = operator.mutations.first
      expect(mutation.parse_status).to eq(:unparseable)
      expect(mutation).to be_unparseable
    end

    it "marks parseable mutations with parse_status :ok" do
      operator_class = Class.new(described_class) do
        def visit_integer_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: node.location.end_offset - node.location.start_offset,
            replacement: "0",
            node: node
          )
        end
      end

      fixture_path = File.expand_path("../../support/fixtures/simple_class.rb", __dir__)
      tree = Prism.parse(File.read(fixture_path)).value
      subject_obj = double("Subject", name: "User#adult?", file_path: fixture_path, node: tree)

      result = operator_class.new.call(subject_obj)

      expect(result).not_to be_empty
      expect(result.map(&:parse_status).uniq).to eq([:ok])
    end

    it "populates slices spanning multi-line mutations" do
      operator_class = Class.new(described_class) do
        def visit_def_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: node.location.end_offset - node.location.start_offset,
            replacement: "nil",
            node: node
          )
        end
      end

      fixture_path = File.expand_path("../../support/fixtures/simple_class.rb", __dir__)
      file_source = File.read(fixture_path)
      tree = Prism.parse(file_source).value
      subject_obj = double("Subject", name: "User#initialize", file_path: fixture_path, node: tree)

      result = operator_class.new.call(subject_obj)
      init_def = result.find { |m| m.line == 4 }

      expect(init_def).not_to be_nil
      expected_original = "  def initialize(name, age)\n    @name = name\n    @age = age\n  end\n"
      expect(init_def.original_slice).to eq(expected_original)
      expect(init_def.mutated_slice).to eq("  nil\n")
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
