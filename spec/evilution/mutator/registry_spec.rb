# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Registry do
  let(:registry) { described_class.new }

  describe ".default" do
    it "returns a registry pre-loaded with all operators" do
      default_registry = described_class.default

      expect(default_registry).to be_a(described_class)
      expect(default_registry.operator_count).to eq(55)
    end

    it "includes all expected operator classes" do
      default_registry = described_class.default
      operators = default_registry.operators

      expected_operators = [
        Evilution::Mutator::Operator::ComparisonReplacement,
        Evilution::Mutator::Operator::ArithmeticReplacement,
        Evilution::Mutator::Operator::BooleanOperatorReplacement,
        Evilution::Mutator::Operator::BooleanLiteralReplacement,
        Evilution::Mutator::Operator::NilReplacement,
        Evilution::Mutator::Operator::IntegerLiteral,
        Evilution::Mutator::Operator::FloatLiteral,
        Evilution::Mutator::Operator::StringLiteral,
        Evilution::Mutator::Operator::ArrayLiteral,
        Evilution::Mutator::Operator::HashLiteral,
        Evilution::Mutator::Operator::SymbolLiteral,
        Evilution::Mutator::Operator::ConditionalNegation,
        Evilution::Mutator::Operator::ConditionalBranch,
        Evilution::Mutator::Operator::StatementDeletion,
        Evilution::Mutator::Operator::MethodBodyReplacement,
        Evilution::Mutator::Operator::NegationInsertion,
        Evilution::Mutator::Operator::ReturnValueRemoval,
        Evilution::Mutator::Operator::CollectionReplacement,
        Evilution::Mutator::Operator::MethodCallRemoval,
        Evilution::Mutator::Operator::ArgumentRemoval,
        Evilution::Mutator::Operator::BlockRemoval,
        Evilution::Mutator::Operator::ConditionalFlip,
        Evilution::Mutator::Operator::RangeReplacement,
        Evilution::Mutator::Operator::RegexpMutation,
        Evilution::Mutator::Operator::ReceiverReplacement,
        Evilution::Mutator::Operator::SendMutation,
        Evilution::Mutator::Operator::ArgumentNilSubstitution,
        Evilution::Mutator::Operator::CompoundAssignment,
        Evilution::Mutator::Operator::MixinRemoval,
        Evilution::Mutator::Operator::SuperclassRemoval,
        Evilution::Mutator::Operator::LocalVariableAssignment,
        Evilution::Mutator::Operator::InstanceVariableWrite,
        Evilution::Mutator::Operator::ClassVariableWrite,
        Evilution::Mutator::Operator::GlobalVariableWrite,
        Evilution::Mutator::Operator::RescueRemoval,
        Evilution::Mutator::Operator::RescueBodyReplacement,
        Evilution::Mutator::Operator::InlineRescue,
        Evilution::Mutator::Operator::EnsureRemoval,
        Evilution::Mutator::Operator::BreakStatement,
        Evilution::Mutator::Operator::NextStatement,
        Evilution::Mutator::Operator::RedoStatement,
        Evilution::Mutator::Operator::BangMethod,
        Evilution::Mutator::Operator::BitwiseReplacement,
        Evilution::Mutator::Operator::BitwiseComplement,
        Evilution::Mutator::Operator::ZsuperRemoval,
        Evilution::Mutator::Operator::ExplicitSuperMutation,
        Evilution::Mutator::Operator::IndexToFetch,
        Evilution::Mutator::Operator::IndexToDig,
        Evilution::Mutator::Operator::IndexAssignmentRemoval,
        Evilution::Mutator::Operator::PatternMatchingGuard,
        Evilution::Mutator::Operator::PatternMatchingAlternative,
        Evilution::Mutator::Operator::PatternMatchingArray,
        Evilution::Mutator::Operator::CollectionReturn,
        Evilution::Mutator::Operator::ScalarReturn,
        Evilution::Mutator::Operator::KeywordArgument
      ]

      expect(operators).to match_array(expected_operators)
    end
  end

  describe "#register" do
    it "adds an operator class" do
      dummy_operator = Class.new(Evilution::Mutator::Base)
      registry.register(dummy_operator)

      expect(registry.operator_count).to eq(1)
    end

    it "returns self for chaining" do
      dummy_operator = Class.new(Evilution::Mutator::Base)
      result = registry.register(dummy_operator)

      expect(result).to eq(registry)
    end
  end

  describe "#mutations_for" do
    it "collects mutations from all registered operators" do
      operator_class = Class.new(Evilution::Mutator::Base) do
        def visit_def_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: 3,
            replacement: "DEF",
            node: node
          )
        end
      end

      registry.register(operator_class)

      fixture_path = File.expand_path("../../support/fixtures/simple_class.rb", __dir__)
      source = File.read(fixture_path)
      tree = Prism.parse(source).value
      first_def = nil
      tree.statements.body.first.body.body.each do |node|
        if node.is_a?(Prism::DefNode)
          first_def = node
          break
        end
      end

      subject_obj = double("Subject",
                           name: "User#initialize",
                           file_path: fixture_path,
                           node: first_def)

      mutations = registry.mutations_for(subject_obj)

      expect(mutations).not_to be_empty
      expect(mutations.first).to be_a(Evilution::Mutation)
    end

    it "returns empty array when no operators registered" do
      subject_obj = double("Subject",
                           file_path: File.expand_path("../../support/fixtures/simple_class.rb", __dir__),
                           node: Prism.parse("def foo; end").value.statements.body.first)

      expect(registry.mutations_for(subject_obj)).to eq([])
    end

    it "passes filter to operators and skips matching mutations" do
      operator_class = Class.new(Evilution::Mutator::Base) do
        def visit_call_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: node.location.end_offset - node.location.start_offset,
            replacement: "nil",
            node: node
          )
        end
      end

      registry.register(operator_class)

      fixture_path = File.expand_path("../../support/fixtures/simple_class.rb", __dir__)
      code = "log()"
      tree = Prism.parse(code).value
      node = tree.statements.body.first
      subject_obj = double("Subject", name: "Test#m", file_path: fixture_path, node: node)

      filter = Evilution::AST::Pattern::Filter.new(["call{name=log}"])
      mutations = registry.mutations_for(subject_obj, filter: filter)

      expect(mutations).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end

  describe "#operators" do
    it "returns a copy of registered operators" do
      dummy = Class.new(Evilution::Mutator::Base)
      registry.register(dummy)

      operators = registry.operators
      operators.clear

      expect(registry.operator_count).to eq(1)
    end
  end
end
