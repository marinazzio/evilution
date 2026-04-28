# frozen_string_literal: true

require_relative "../registry"
require_relative "../diff_helpers"

module Evilution::Reporter::Suggestion::Templates::Minitest
  H = Evilution::Reporter::Suggestion::DiffHelpers

  def self.format_header(action, original, mutated, subject_name)
    case action
    when :changed             then "changed `#{original}` to `#{mutated}` in #{subject_name}"
    when :deleted             then "deleted `#{original}` in #{subject_name}"
    when :removed             then "removed `#{original}` in #{subject_name}"
    when :removed_superclass  then "removed superclass from `#{original}` in #{subject_name}"
    when :removed_ensure      then "removed ensure block `#{original}` in #{subject_name}"
    end
  end

  def self.build(test_name:, action: :changed, &body_block)
    lambda do |mutation|
      method_name = H.parse_method_name(mutation.subject.name)
      safe_name = H.sanitize_method_name(method_name)
      original_line, mutated_line = H.extract_diff_lines(mutation.diff)
      body = body_block.call(method_name)
      indented = body.lines.map { |l| "  #{l}" }.join.chomp

      <<~MINITEST.strip
        # Mutation: #{format_header(action, original_line, mutated_line, mutation.subject.name)}
        # #{mutation.file_path}:#{mutation.line}
        def test_#{test_name}_#{safe_name}
        #{indented}
        end
      MINITEST
    end
  end

  MINITEST_ENTRIES = {
    "comparison_replacement" => build(test_name: "returns_correct_result_at_comparison_boundary_in") do |method_name|
      <<~BODY
        # Test with values where the original operator and mutated operator
        # produce different results (e.g., equal values for > vs >=)
        result = subject.#{method_name}(boundary_value)
        assert_equal expected, result
      BODY
    end,
    "arithmetic_replacement" => build(test_name: "computes_correct_arithmetic_result_in") do |method_name|
      <<~BODY
        # Assert the exact numeric result, not just truthiness or sign
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "boolean_operator_replacement" => build(test_name: "returns_correct_result_when_one_condition_differs_in") do |method_name|
      <<~BODY
        # Use inputs where only one operand is truthy to distinguish && from ||
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "boolean_literal_replacement" => build(test_name: "returns_expected_boolean_value_from") do |method_name|
      <<~BODY
        # Assert the exact true/false/nil value, not just truthiness
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "negation_insertion" => build(test_name: "returns_correct_boolean_from_predicate_in") do |method_name|
      <<~BODY
        # Assert the exact true/false result, not just truthiness
        result = subject.#{method_name}(input_value)
        assert_includes [true, false], result
      BODY
    end,
    "integer_literal" => build(test_name: "returns_exact_integer_value_from") do |method_name|
      <<~BODY
        # Assert the exact numeric value, not just > 0 or truthy
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "float_literal" => build(test_name: "returns_exact_float_value_from") do |method_name|
      <<~BODY
        # Assert the exact floating-point result
        result = subject.#{method_name}(input_value)
        assert_in_delta expected, result
      BODY
    end,
    "string_literal" => build(test_name: "returns_exact_string_content_from") do |method_name|
      <<~BODY
        # Assert the exact string value, not just presence or non-empty
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "symbol_literal" => build(test_name: "returns_exact_symbol_from") do |method_name|
      <<~BODY
        # Assert the exact symbol value, not just that it is a Symbol
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "array_literal" => build(test_name: "returns_expected_array_contents_from") do |method_name|
      <<~BODY
        # Assert the exact array elements, not just non-empty or truthy
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "hash_literal" => build(test_name: "returns_expected_hash_contents_from") do |method_name|
      <<~BODY
        # Assert the exact keys and values, not just non-empty or truthy
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "collection_replacement" => build(test_name: "uses_return_value_of_collection_operation_in") do |method_name|
      <<~BODY
        # Assert the return value of the collection method, not just side effects
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "conditional_negation" => build(test_name: "exercises_both_branches_of_conditional_in") do |method_name|
      <<~BODY
        # Test with inputs that make the condition true AND false
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "conditional_branch" => build(test_name: "exercises_removed_branch_of_conditional_in") do |method_name|
      <<~BODY
        # Test with inputs that trigger the branch removed by this mutation
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "statement_deletion" => build(test_name: "depends_on_side_effect_of_deleted_statement_in", action: :deleted) do |method_name|
      <<~BODY
        # Assert a side effect or return value that changes when this statement is removed
        subject.#{method_name}(input_value)
        assert_equal expected, observable_side_effect
      BODY
    end,
    "method_body_replacement" => build(test_name: "verifies_return_value_or_side_effects_of") do |method_name|
      <<~BODY
        # Assert the method produces a meaningful result, not just nil
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "return_value_removal" => build(test_name: "uses_return_value_of") do |method_name|
      <<~BODY
        # Assert the caller depends on the return value, not just side effects
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "method_call_removal" => build(test_name: "depends_on_return_value_or_side_effect_of_call_in") do |method_name|
      <<~BODY
        # Assert the method call's effect is observable
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "compound_assignment" => build(test_name: "verifies_compound_assignment_side_effect_in") do |method_name|
      <<~BODY
        # Assert the accumulated value after the compound assignment
        # The mutation changes the operator, so the final value will differ
        subject.#{method_name}(input_value)
        assert_equal expected, observable_side_effect
      BODY
    end,
    "nil_replacement" => build(test_name: "asserts_nil_return_value_from") do |method_name|
      <<~BODY
        # Assert the method returns nil, not a substituted value
        result = subject.#{method_name}(input_value)
        assert_nil result
      BODY
    end,
    "superclass_removal" => build(test_name: "depends_on_inherited_behavior_in", action: :removed_superclass) do |method_name|
      <<~BODY
        # Assert behavior that comes from the superclass
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "local_variable_assignment" => build(test_name: "verifies_local_variable_assignment_is_used_in") do |method_name|
      <<~BODY
        # Assert that the assigned variable is read later, not just the value expression
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "instance_variable_write" => build(test_name: "verifies_instance_variable_is_set_correctly_in") do |method_name|
      <<~BODY
        # Assert that the instance variable holds the expected value after the method runs
        subject.#{method_name}(input_value)
        assert_equal expected, subject.instance_variable_get(:@variable)
      BODY
    end,
    "class_variable_write" => build(test_name: "verifies_class_variable_shared_state_in") do |method_name|
      <<~BODY
        # Assert that the class variable holds the expected value and affects shared state
        subject.#{method_name}(input_value)
        assert_equal expected, klass.class_variable_get(:@@variable)
      BODY
    end,
    "global_variable_write" => build(test_name: "verifies_global_variable_is_set_correctly_in") do |method_name|
      <<~BODY
        # Assert that the global variable holds the expected value after the method runs
        subject.#{method_name}(input_value)
        assert_equal expected, $variable
      BODY
    end,
    "mixin_removal" => build(test_name: "depends_on_behavior_from_included_module_in", action: :removed) do |method_name|
      <<~BODY
        # Assert behavior provided by the mixin
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "rescue_removal" => build(test_name: "verifies_rescue_handler_is_needed_in", action: :removed) do |method_name|
      <<~BODY
        # Trigger the rescued exception and assert the handler's effect
        result = subject.#{method_name}(input_that_raises)
        assert_equal expected, result
      BODY
    end,
    "rescue_body_replacement" => build(test_name: "verifies_rescue_handler_produces_correct_result_in") do |method_name|
      <<~BODY
        # Trigger the exception and assert the rescue body's return value or side effect
        result = subject.#{method_name}(input_that_raises)
        assert_equal expected, result
      BODY
    end,
    "inline_rescue" => build(test_name: "verifies_inline_rescue_fallback_value_in") do |method_name|
      <<~BODY
        # Trigger the exception and assert the fallback value is correct
        result = subject.#{method_name}(input_that_raises)
        assert_equal expected, result
      BODY
    end,
    "ensure_removal" => build(test_name: "verifies_ensure_cleanup_runs_in", action: :removed_ensure) do |method_name|
      <<~BODY
        # Assert that the cleanup side effect is observable after the method runs
        subject.#{method_name}(input_value)
        assert_equal expected, observable_cleanup_effect
      BODY
    end,
    "break_statement" => build(test_name: "verifies_break_exits_loop_correctly_in") do |method_name|
      <<~BODY
        # Assert the loop exits early and returns the expected value
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "next_statement" => build(test_name: "verifies_next_skips_iteration_correctly_in") do |method_name|
      <<~BODY
        # Assert the iteration is skipped and the expected value is yielded
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "redo_statement" => build(test_name: "verifies_redo_retry_logic_is_necessary_in") do |method_name|
      <<~BODY
        # Assert the iteration restart changes the outcome
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "bitwise_replacement" => build(test_name: "verifies_exact_bitwise_result_in") do |method_name|
      <<~BODY
        # Assert the exact bit-level result to distinguish &, |, and ^ operators
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "bitwise_complement" => build(test_name: "verifies_bitwise_complement_result_in") do |method_name|
      <<~BODY
        # Assert the exact complement (~) value, not just sign or magnitude
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "bang_method" => build(test_name: "verifies_in_place_vs_copy_semantics_matter_in") do |method_name|
      <<~BODY
        # Assert that the original object is or is not modified
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "zsuper_removal" => build(test_name: "verifies_inherited_behavior_from_super_in") do |method_name|
      <<~BODY
        # Assert that the result depends on the superclass implementation
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "explicit_super_mutation" => build(test_name: "verifies_correct_arguments_passed_to_super_in") do |method_name|
      <<~BODY
        # Assert the inherited method receives the expected arguments
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "index_to_fetch" => build(test_name: "distinguishes_bracket_from_fetch_for_missing_keys_in") do |method_name|
      <<~BODY
        # Access a missing key: [] returns nil, .fetch raises KeyError
        assert_raises(KeyError) { subject.#{method_name}(collection_with_missing_key) }
      BODY
    end,
    "index_to_dig" => build(test_name: "verifies_chained_bracket_access_returns_correct_nested_value_in") do |method_name|
      <<~BODY
        # Assert the nested lookup produces the expected value
        result = subject.#{method_name}(nested_collection)
        assert_equal expected, result
      BODY
    end,
    "index_assignment_removal" => build(test_name: "verifies_bracket_assignment_modifies_collection_in") do |method_name|
      <<~BODY
        # Assert the collection contains the assigned value at the expected key after the method runs
        result = subject.#{method_name}(collection)
        assert_equal expected_value, result[expected_key]
      BODY
    end,
    "pattern_matching_guard" => build(test_name: "verifies_pattern_guard_filters_correctly_in") do |method_name|
      <<~BODY
        # Test with input that matches the pattern but fails the guard condition
        # The guard should prevent matching, routing to a different branch
        result = subject.#{method_name}(input_matching_pattern_but_failing_guard)
        assert_equal expected, result
      BODY
    end,
    "pattern_matching_alternative" => build(test_name: "verifies_each_pattern_alternative_is_reachable_in") do |method_name|
      <<~BODY
        # Test with input that matches only one specific alternative
        # Each alternative should have a dedicated test case
        result = subject.#{method_name}(input_for_specific_alternative)
        assert_equal expected, result
      BODY
    end,
    "collection_return" => build(test_name: "returns_non_empty_collection_from") do |method_name|
      <<~BODY
        # Assert the collection has the expected elements, not just non-empty
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "scalar_return" => build(test_name: "returns_non_zero_non_empty_value_from") do |method_name|
      <<~BODY
        # Assert the exact scalar value, not just presence or type
        result = subject.#{method_name}(input_value)
        assert_equal expected, result
      BODY
    end,
    "pattern_matching_array" => build(test_name: "verifies_each_array_pattern_element_matters_in") do |method_name|
      <<~BODY
        # Test with input where changing one element type causes a different match
        # Each position in the array pattern should be validated
        result = subject.#{method_name}(input_with_wrong_element_type)
        assert_equal expected, result
      BODY
    end
  }.freeze
end
