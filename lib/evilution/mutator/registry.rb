# frozen_string_literal: true

module Evilution
  module Mutator
    class Registry
      def self.default
        registry = new
        [
          Operator::ComparisonReplacement,
          Operator::ArithmeticReplacement,
          Operator::BooleanOperatorReplacement,
          Operator::BooleanLiteralReplacement,
          Operator::NilReplacement,
          Operator::IntegerLiteral,
          Operator::FloatLiteral,
          Operator::StringLiteral,
          Operator::ArrayLiteral,
          Operator::HashLiteral,
          Operator::SymbolLiteral,
          Operator::ConditionalNegation,
          Operator::ConditionalBranch,
          Operator::StatementDeletion,
          Operator::MethodBodyReplacement,
          Operator::NegationInsertion,
          Operator::ReturnValueRemoval,
          Operator::CollectionReplacement,
          Operator::MethodCallRemoval,
          Operator::ArgumentRemoval,
          Operator::BlockRemoval,
          Operator::ConditionalFlip,
          Operator::RangeReplacement
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
  end
end
