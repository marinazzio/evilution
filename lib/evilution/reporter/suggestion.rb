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
        "method_call_removal" => "Add a test that depends on the return value or side effect of this method call",
        "argument_removal" => "Add a test that verifies the correct arguments are passed to this method call"
      }.freeze

      CONCRETE_TEMPLATES = {
        "comparison_replacement" => lambda { |mutation|
          method_name = parse_method_name(mutation.subject.name)
          original_line, mutated_line = extract_diff_lines(mutation.diff)
          <<~RSPEC.strip
            # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
            # #{mutation.file_path}:#{mutation.line}
            it 'returns the correct result at the comparison boundary in ##{method_name}' do
              # Test with values where the original operator and mutated operator
              # produce different results (e.g., equal values for > vs >=)
              result = subject.#{method_name}(boundary_value)
              expect(result).to eq(expected)
            end
          RSPEC
        },
        "arithmetic_replacement" => lambda { |mutation|
          method_name = parse_method_name(mutation.subject.name)
          original_line, mutated_line = extract_diff_lines(mutation.diff)
          <<~RSPEC.strip
            # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
            # #{mutation.file_path}:#{mutation.line}
            it 'computes the correct arithmetic result in ##{method_name}' do
              # Assert the exact numeric result, not just truthiness or sign
              result = subject.#{method_name}(input_value)
              expect(result).to eq(expected)
            end
          RSPEC
        }
      }.freeze

      DEFAULT_SUGGESTION = "Add a more specific test that detects this mutation"

      def initialize(suggest_tests: false)
        @suggest_tests = suggest_tests
      end

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
        if @suggest_tests
          concrete = CONCRETE_TEMPLATES[mutation.operator_name]
          return concrete.call(mutation) if concrete
        end

        TEMPLATES.fetch(mutation.operator_name, DEFAULT_SUGGESTION)
      end

      class << self
        def parse_method_name(subject_name)
          subject_name.split(/[#.]/).last
        end

        def extract_diff_lines(diff)
          lines = diff.split("\n")
          original = lines.find { |l| l.start_with?("- ") }
          mutated = lines.find { |l| l.start_with?("+ ") }
          [original&.sub(/^- /, "")&.strip, mutated&.sub(/^\+ /, "")&.strip]
        end
      end
    end
  end
end
