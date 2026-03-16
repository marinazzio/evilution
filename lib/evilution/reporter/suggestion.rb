# frozen_string_literal: true

module Evilution
  module Reporter
    class Suggestion
      TEMPLATES = {
        "comparison_replacement" => "Add a test for the boundary condition where the comparison operand equals the threshold exactly",
        "arithmetic_replacement" => "Add a test that verifies the arithmetic result, not just truthiness of the outcome",
        "boolean_operator_replacement" => "Add a test where only one of the boolean conditions is true to distinguish && from ||",
        "boolean_literal_replacement" => "Add a test that exercises the false/true branch explicitly",
        "nil_replacement" => "Add a test that asserts the return value is not nil",
        "integer_literal" => "Add a test that checks the exact numeric value, not just > 0 or truthy",
        "float_literal" => "Add a test that checks the exact floating-point value returned",
        "string_literal" => "Add a test that asserts the string content, not just its presence",
        "array_literal" => "Add a test that verifies the array contents or length",
        "hash_literal" => "Add a test that verifies the hash keys and values",
        "symbol_literal" => "Add a test that checks the exact symbol returned",
        "conditional_negation" => "Add tests for both the true and false branches of this conditional",
        "conditional_branch" => "Add a test that exercises the removed branch of this conditional",
        "statement_deletion" => "Add a test that depends on the side effect of this statement",
        "method_body_replacement" => "Add a test that checks the method's return value or side effects",
        "negation_insertion" => "Add a test where the predicate result matters (not just truthiness)",
        "return_value_removal" => "Add a test that uses the return value of this method",
        "collection_replacement" => "Add a test that checks the return value of the collection operation, not just side effects",
        "method_call_removal" => "Add a test that depends on the return value or side effect of this method call"
      }.freeze

      DEFAULT_SUGGESTION = "Add a more specific test that detects this mutation"

      # Generate suggestions for survived mutations.
      #
      # @param summary [Result::Summary]
      # @return [Array<Hash>] Array of { mutation:, suggestion: }
      def call(summary)
        summary.survived_results.map do |result|
          {
            mutation: result.mutation,
            suggestion: suggestion_for(result.mutation)
          }
        end
      end

      # Generate a suggestion for a single mutation.
      #
      # @param mutation [Mutation]
      # @return [String]
      def suggestion_for(mutation)
        TEMPLATES.fetch(mutation.operator_name, DEFAULT_SUGGESTION)
      end
    end
  end
end
