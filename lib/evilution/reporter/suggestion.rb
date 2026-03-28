# frozen_string_literal: true

require_relative "../reporter"

class Evilution::Reporter::Suggestion
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
    "argument_removal" => "Add a test that verifies the correct arguments are passed to this method call",
    "compound_assignment" => "Add a test that verifies the side effect of this compound assignment (the accumulated value matters)",
    "superclass_removal" => "Add a test that exercises inherited behavior from the superclass",
    "mixin_removal" => "Add a test that exercises behavior provided by the included/extended module",
    "local_variable_assignment" => "Add a test that depends on the assigned variable being stored, not just the value expression"
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
    },
    "boolean_operator_replacement" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'returns the correct result when one condition is true and one is false in ##{method_name}' do
          # Use inputs where only one operand is truthy to distinguish && from ||
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "boolean_literal_replacement" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'returns the expected boolean value from ##{method_name}' do
          # Assert the exact true/false/nil value, not just truthiness
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "negation_insertion" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'returns the correct boolean from the predicate in ##{method_name}' do
          # Assert the exact true/false result, not just truthiness
          result = subject.#{method_name}(input_value)
          expect(result).to eq(true).or eq(false)
        end
      RSPEC
    },
    "integer_literal" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'returns the exact integer value from ##{method_name}' do
          # Assert the exact numeric value, not just > 0 or truthy
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "float_literal" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'returns the exact float value from ##{method_name}' do
          # Assert the exact floating-point result
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "string_literal" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'returns the exact string content from ##{method_name}' do
          # Assert the exact string value, not just presence or non-empty
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "symbol_literal" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'returns the exact symbol from ##{method_name}' do
          # Assert the exact symbol value, not just that it is a Symbol
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "array_literal" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'returns the expected array contents from ##{method_name}' do
          # Assert the exact array elements, not just non-empty or truthy
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "hash_literal" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'returns the expected hash contents from ##{method_name}' do
          # Assert the exact keys and values, not just non-empty or truthy
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "collection_replacement" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'uses the return value of the collection operation in ##{method_name}' do
          # Assert the return value of the collection method, not just side effects
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "conditional_negation" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'exercises both branches of the conditional in ##{method_name}' do
          # Test with inputs that make the condition true AND false
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "conditional_branch" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'exercises the removed branch of the conditional in ##{method_name}' do
          # Test with inputs that trigger the branch removed by this mutation
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "statement_deletion" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, _mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: deleted `#{original_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'depends on the side effect of the deleted statement in ##{method_name}' do
          # Assert a side effect or return value that changes when this statement is removed
          subject.#{method_name}(input_value)
          expect(observable_side_effect).to eq(expected)
        end
      RSPEC
    },
    "method_body_replacement" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the return value or side effects of ##{method_name}' do
          # Assert the method produces a meaningful result, not just nil
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "return_value_removal" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'uses the return value of ##{method_name}' do
          # Assert the caller depends on the return value, not just side effects
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "method_call_removal" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'depends on the return value or side effect of the call in ##{method_name}' do
          # Assert the method call's effect is observable
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "compound_assignment" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the compound assignment side effect in ##{method_name}' do
          # Assert the accumulated value after the compound assignment
          # The mutation changes the operator, so the final value will differ
          subject.#{method_name}(input_value)
          expect(observable_side_effect).to eq(expected)
        end
      RSPEC
    },
    "nil_replacement" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'asserts the nil return value from ##{method_name}' do
          # Assert the method returns nil, not a substituted value
          result = subject.#{method_name}(input_value)
          expect(result).to be_nil
        end
      RSPEC
    },
    "superclass_removal" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, _mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: removed superclass from `#{original_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'depends on inherited behavior in ##{method_name}' do
          # Assert behavior that comes from the superclass
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "mixin_removal" => lambda { |mutation|
      method_name = parse_method_name(mutation.subject.name)
      original_line, _mutated_line = extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: removed `#{original_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'depends on behavior from the included module in ##{method_name}' do
          # Assert behavior provided by the mixin
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
