# frozen_string_literal: true

require_relative "../registry"
require_relative "../diff_helpers"

module Evilution::Reporter::Suggestion::Templates::Rspec
  H = Evilution::Reporter::Suggestion::DiffHelpers

  RSPEC_ENTRIES = {
    "comparison_replacement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, _mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
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
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, _mutated_line = H.extract_diff_lines(mutation.diff)
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
    "local_variable_assignment" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the local variable assignment is used in ##{method_name}' do
          # Assert that the assigned variable is read later, not just the value expression
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "instance_variable_write" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the instance variable @state is set correctly in ##{method_name}' do
          # Assert that the instance variable holds the expected value after the method runs
          subject.#{method_name}(input_value)
          expect(subject.instance_variable_get(:@variable)).to eq(expected)
        end
      RSPEC
    },
    "class_variable_write" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the class variable @@shared state is set correctly in ##{method_name}' do
          # Assert that the class variable holds the expected value and affects shared state
          subject.#{method_name}(input_value)
          expect(described_class.class_variable_get(:@@variable)).to eq(expected)
        end
      RSPEC
    },
    "global_variable_write" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the global variable $state is set correctly in ##{method_name}' do
          # Assert that the global variable holds the expected value after the method runs
          subject.#{method_name}(input_value)
          expect($variable).to eq(expected)
        end
      RSPEC
    },
    "mixin_removal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, _mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: removed `#{original_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'depends on behavior from the included module in ##{method_name}' do
          # Assert behavior provided by the mixin
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "rescue_removal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, _mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: removed `#{original_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the rescue handler is needed in ##{method_name}' do
          # Trigger the rescued exception and assert the handler's effect
          result = subject.#{method_name}(input_that_raises)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "rescue_body_replacement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the rescue handler produces the correct result in ##{method_name}' do
          # Trigger the exception and assert the rescue body's return value or side effect
          result = subject.#{method_name}(input_that_raises)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "inline_rescue" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the inline rescue fallback value in ##{method_name}' do
          # Trigger the exception and assert the fallback value is correct
          result = subject.#{method_name}(input_that_raises)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "ensure_removal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, _mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: removed ensure block `#{original_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the ensure cleanup runs in ##{method_name}' do
          # Assert that the cleanup side effect is observable after the method runs
          subject.#{method_name}(input_value)
          expect(observable_cleanup_effect).to eq(expected)
        end
      RSPEC
    },
    "break_statement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the break exits the loop correctly in ##{method_name}' do
          # Assert the loop exits early and returns the expected value
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "next_statement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the next skips the iteration correctly in ##{method_name}' do
          # Assert the iteration is skipped and the expected value is yielded
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "redo_statement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the redo retry logic is necessary in ##{method_name}' do
          # Assert the iteration restart changes the outcome
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "bitwise_replacement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the exact bitwise result in ##{method_name}' do
          # Assert the exact bit-level result to distinguish &, |, and ^ operators
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "bitwise_complement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the bitwise complement result in ##{method_name}' do
          # Assert the exact complement (~) value, not just sign or magnitude
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "bang_method" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies in-place vs copy semantics matter in ##{method_name}' do
          # Assert that the original object is or is not modified
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "zsuper_removal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies inherited behavior from super is needed in ##{method_name}' do
          # Assert that the result depends on the superclass implementation
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "explicit_super_mutation" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the correct arguments are passed to super in ##{method_name}' do
          # Assert the inherited method receives the expected arguments
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "index_to_fetch" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'distinguishes [] from .fetch for missing keys in ##{method_name}' do
          # Access a missing key: [] returns nil, .fetch raises KeyError
          expect { subject.#{method_name}(collection_with_missing_key) }.to raise_error(KeyError)
        end
      RSPEC
    },
    "index_to_dig" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the chained [] access returns the correct nested value in ##{method_name}' do
          # Assert the nested lookup produces the expected value
          result = subject.#{method_name}(nested_collection)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "index_assignment_removal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the []= assignment modifies the collection in ##{method_name}' do
          # Assert the collection contains the assigned value after the method runs
          result = subject.#{method_name}(collection)
          expect(result).to include(expected_key => expected_value)
        end
      RSPEC
    },
    "pattern_matching_guard" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies the pattern guard filters correctly in ##{method_name}' do
          # Test with input that matches the pattern but fails the guard condition
          # The guard should prevent matching, routing to a different branch
          result = subject.#{method_name}(input_matching_pattern_but_failing_guard)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "pattern_matching_alternative" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies each pattern alternative is reachable in ##{method_name}' do
          # Test with input that matches only one specific alternative
          # Each alternative should have a dedicated test case
          result = subject.#{method_name}(input_for_specific_alternative)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "collection_return" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'returns a non-empty collection from ##{method_name}' do
          # Assert the collection has the expected elements, not just non-empty
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "scalar_return" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'returns a non-zero/non-empty value from ##{method_name}' do
          # Assert the exact scalar value, not just presence or type
          result = subject.#{method_name}(input_value)
          expect(result).to eq(expected)
        end
      RSPEC
    },
    "pattern_matching_array" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~RSPEC.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        it 'verifies each array pattern element matters in ##{method_name}' do
          # Test with input where changing one element type causes a different match
          # Each position in the array pattern should be validated
          result = subject.#{method_name}(input_with_wrong_element_type)
          expect(result).to eq(expected)
        end
      RSPEC
    }
  }.freeze
end
