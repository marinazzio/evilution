# frozen_string_literal: true

require_relative "../mutator"

class Evilution::Mutator::Registry
  def self.default
    registry = new
    [
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
      Evilution::Mutator::Operator::BangMethod
    ].each { |op| registry.register(op) }
    registry
  end

  def initialize
    @operators = []
  end

  def register(operator_class)
    @operators << operator_class
    self
  end

  def mutations_for(subject)
    @operators.flat_map do |operator_class|
      operator_class.new.call(subject)
    end
  end

  def operator_count
    @operators.length
  end

  def operators
    @operators.dup
  end
end
