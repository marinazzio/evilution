# frozen_string_literal: true

require_relative "../registry"
require_relative "../diff_helpers"

module Evilution::Reporter::Suggestion::Templates::Minitest
  H = Evilution::Reporter::Suggestion::DiffHelpers

  MINITEST_ENTRIES = {
    "comparison_replacement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_returns_correct_result_at_comparison_boundary_in_#{safe_name}
          # Test with values where the original operator and mutated operator
          # produce different results (e.g., equal values for > vs >=)
          result = subject.#{method_name}(boundary_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "arithmetic_replacement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_computes_correct_arithmetic_result_in_#{safe_name}
          # Assert the exact numeric result, not just truthiness or sign
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "boolean_operator_replacement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_returns_correct_result_when_one_condition_differs_in_#{safe_name}
          # Use inputs where only one operand is truthy to distinguish && from ||
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "boolean_literal_replacement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_returns_expected_boolean_value_from_#{safe_name}
          # Assert the exact true/false/nil value, not just truthiness
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "negation_insertion" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_returns_correct_boolean_from_predicate_in_#{safe_name}
          # Assert the exact true/false result, not just truthiness
          result = subject.#{method_name}(input_value)
          assert_includes [true, false], result
        end
      MINITEST
    },
    "integer_literal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_returns_exact_integer_value_from_#{safe_name}
          # Assert the exact numeric value, not just > 0 or truthy
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "float_literal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_returns_exact_float_value_from_#{safe_name}
          # Assert the exact floating-point result
          result = subject.#{method_name}(input_value)
          assert_in_delta expected, result
        end
      MINITEST
    },
    "string_literal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_returns_exact_string_content_from_#{safe_name}
          # Assert the exact string value, not just presence or non-empty
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "symbol_literal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_returns_exact_symbol_from_#{safe_name}
          # Assert the exact symbol value, not just that it is a Symbol
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "array_literal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_returns_expected_array_contents_from_#{safe_name}
          # Assert the exact array elements, not just non-empty or truthy
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "hash_literal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_returns_expected_hash_contents_from_#{safe_name}
          # Assert the exact keys and values, not just non-empty or truthy
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "collection_replacement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_uses_return_value_of_collection_operation_in_#{safe_name}
          # Assert the return value of the collection method, not just side effects
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "conditional_negation" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_exercises_both_branches_of_conditional_in_#{safe_name}
          # Test with inputs that make the condition true AND false
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "conditional_branch" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_exercises_removed_branch_of_conditional_in_#{safe_name}
          # Test with inputs that trigger the branch removed by this mutation
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "statement_deletion" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, _mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: deleted `#{original_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_depends_on_side_effect_of_deleted_statement_in_#{safe_name}
          # Assert a side effect or return value that changes when this statement is removed
          subject.#{method_name}(input_value)
          assert_equal expected, observable_side_effect
        end
      MINITEST
    },
    "method_body_replacement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_return_value_or_side_effects_of_#{safe_name}
          # Assert the method produces a meaningful result, not just nil
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "return_value_removal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_uses_return_value_of_#{safe_name}
          # Assert the caller depends on the return value, not just side effects
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "method_call_removal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_depends_on_return_value_or_side_effect_of_call_in_#{safe_name}
          # Assert the method call's effect is observable
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "compound_assignment" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_compound_assignment_side_effect_in_#{safe_name}
          # Assert the accumulated value after the compound assignment
          # The mutation changes the operator, so the final value will differ
          subject.#{method_name}(input_value)
          assert_equal expected, observable_side_effect
        end
      MINITEST
    },
    "nil_replacement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_asserts_nil_return_value_from_#{safe_name}
          # Assert the method returns nil, not a substituted value
          result = subject.#{method_name}(input_value)
          assert_nil result
        end
      MINITEST
    },
    "superclass_removal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, _mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: removed superclass from `#{original_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_depends_on_inherited_behavior_in_#{safe_name}
          # Assert behavior that comes from the superclass
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "local_variable_assignment" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_local_variable_assignment_is_used_in_#{safe_name}
          # Assert that the assigned variable is read later, not just the value expression
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "instance_variable_write" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_instance_variable_is_set_correctly_in_#{safe_name}
          # Assert that the instance variable holds the expected value after the method runs
          subject.#{method_name}(input_value)
          assert_equal expected, subject.instance_variable_get(:@variable)
        end
      MINITEST
    },
    "class_variable_write" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_class_variable_shared_state_in_#{safe_name}
          # Assert that the class variable holds the expected value and affects shared state
          subject.#{method_name}(input_value)
          assert_equal expected, klass.class_variable_get(:@@variable)
        end
      MINITEST
    },
    "global_variable_write" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_global_variable_is_set_correctly_in_#{safe_name}
          # Assert that the global variable holds the expected value after the method runs
          subject.#{method_name}(input_value)
          assert_equal expected, $variable
        end
      MINITEST
    },
    "mixin_removal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, _mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: removed `#{original_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_depends_on_behavior_from_included_module_in_#{safe_name}
          # Assert behavior provided by the mixin
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "rescue_removal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, _mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: removed `#{original_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_rescue_handler_is_needed_in_#{safe_name}
          # Trigger the rescued exception and assert the handler's effect
          result = subject.#{method_name}(input_that_raises)
          assert_equal expected, result
        end
      MINITEST
    },
    "rescue_body_replacement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_rescue_handler_produces_correct_result_in_#{safe_name}
          # Trigger the exception and assert the rescue body's return value or side effect
          result = subject.#{method_name}(input_that_raises)
          assert_equal expected, result
        end
      MINITEST
    },
    "inline_rescue" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_inline_rescue_fallback_value_in_#{safe_name}
          # Trigger the exception and assert the fallback value is correct
          result = subject.#{method_name}(input_that_raises)
          assert_equal expected, result
        end
      MINITEST
    },
    "ensure_removal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, _mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: removed ensure block `#{original_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_ensure_cleanup_runs_in_#{safe_name}
          # Assert that the cleanup side effect is observable after the method runs
          subject.#{method_name}(input_value)
          assert_equal expected, observable_cleanup_effect
        end
      MINITEST
    },
    "break_statement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_break_exits_loop_correctly_in_#{safe_name}
          # Assert the loop exits early and returns the expected value
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "next_statement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_next_skips_iteration_correctly_in_#{safe_name}
          # Assert the iteration is skipped and the expected value is yielded
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "redo_statement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_redo_retry_logic_is_necessary_in_#{safe_name}
          # Assert the iteration restart changes the outcome
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "bitwise_replacement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_exact_bitwise_result_in_#{safe_name}
          # Assert the exact bit-level result to distinguish &, |, and ^ operators
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "bitwise_complement" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_bitwise_complement_result_in_#{safe_name}
          # Assert the exact complement (~) value, not just sign or magnitude
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "bang_method" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_in_place_vs_copy_semantics_matter_in_#{safe_name}
          # Assert that the original object is or is not modified
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "zsuper_removal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_inherited_behavior_from_super_in_#{safe_name}
          # Assert that the result depends on the superclass implementation
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "explicit_super_mutation" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_correct_arguments_passed_to_super_in_#{safe_name}
          # Assert the inherited method receives the expected arguments
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "index_to_fetch" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_distinguishes_bracket_from_fetch_for_missing_keys_in_#{safe_name}
          # Access a missing key: [] returns nil, .fetch raises KeyError
          assert_raises(KeyError) { subject.#{method_name}(collection_with_missing_key) }
        end
      MINITEST
    },
    "index_to_dig" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_chained_bracket_access_returns_correct_nested_value_in_#{safe_name}
          # Assert the nested lookup produces the expected value
          result = subject.#{method_name}(nested_collection)
          assert_equal expected, result
        end
      MINITEST
    },
    "index_assignment_removal" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_bracket_assignment_modifies_collection_in_#{safe_name}
          # Assert the collection contains the assigned value at the expected key after the method runs
          result = subject.#{method_name}(collection)
          assert_equal expected_value, result[expected_key]
        end
      MINITEST
    },
    "pattern_matching_guard" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_pattern_guard_filters_correctly_in_#{safe_name}
          # Test with input that matches the pattern but fails the guard condition
          # The guard should prevent matching, routing to a different branch
          result = subject.#{method_name}(input_matching_pattern_but_failing_guard)
          assert_equal expected, result
        end
      MINITEST
    },
    "pattern_matching_alternative" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_each_pattern_alternative_is_reachable_in_#{safe_name}
          # Test with input that matches only one specific alternative
          # Each alternative should have a dedicated test case
          result = subject.#{method_name}(input_for_specific_alternative)
          assert_equal expected, result
        end
      MINITEST
    },
    "collection_return" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_returns_non_empty_collection_from_#{safe_name}
          # Assert the collection has the expected elements, not just non-empty
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "scalar_return" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_returns_non_zero_non_empty_value_from_#{safe_name}
          # Assert the exact scalar value, not just presence or type
          result = subject.#{method_name}(input_value)
          assert_equal expected, result
        end
      MINITEST
    },
    "pattern_matching_array" => lambda { |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      <<~MINITEST.strip
        # Mutation: changed `#{original_line}` to `#{mutated_line}` in #{mutation.subject.name}
        # #{mutation.file_path}:#{mutation.line}
        def test_verifies_each_array_pattern_element_matters_in_#{safe_name}
          # Test with input where changing one element type causes a different match
          # Each position in the array pattern should be validated
          result = subject.#{method_name}(input_with_wrong_element_type)
          assert_equal expected, result
        end
      MINITEST
    }
  }.freeze
end
