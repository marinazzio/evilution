# frozen_string_literal: true

require_relative "../templates"
require_relative "../diff_helpers"
require_relative "../diff_lines"

module Evilution::Reporter::Suggestion::Templates::Rspec
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

  def self.build(it_desc:, action: :changed, &body_block)
    ->(mutation) { render(it_desc, action, body_block, mutation) }
  end

  def self.render(it_desc, action, body_block, mutation)
    method_name = H.parse_method_name(mutation.subject.name)
    diff_lines = Evilution::Reporter::Suggestion::DiffLines.from_diff(mutation.diff)
    indented = indent_body(body_block.call(method_name))

    <<~RSPEC.strip
      # Mutation: #{format_header(action, diff_lines.original, diff_lines.mutated, mutation.subject.name)}
      # #{mutation.file_path}:#{mutation.line}
      it '#{it_desc} ##{method_name}' do
      #{indented}
      end
    RSPEC
  end

  def self.indent_body(body)
    body.lines.map { |l| "  #{l}" }.join.chomp
  end

  RSPEC_ENTRIES = {
    "comparison_replacement" => build(it_desc: "returns the correct result at the comparison boundary in") do |method_name|
      <<~BODY
        # Test with values where the original operator and mutated operator
        # produce different results (e.g., equal values for > vs >=)
        result = subject.#{method_name}(boundary_value)
        expect(result).to eq(expected)
      BODY
    end,
    "arithmetic_replacement" => build(it_desc: "computes the correct arithmetic result in") do |method_name|
      <<~BODY
        # Assert the exact numeric result, not just truthiness or sign
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "boolean_operator_replacement" => build(
      it_desc: "returns the correct result when one condition is true and one is false in"
    ) do |method_name|
      <<~BODY
        # Use inputs where only one operand is truthy to distinguish && from ||
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "boolean_literal_replacement" => build(it_desc: "returns the expected boolean value from") do |method_name|
      <<~BODY
        # Assert the exact true/false/nil value, not just truthiness
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "negation_insertion" => build(it_desc: "returns the correct boolean from the predicate in") do |method_name|
      <<~BODY
        # Assert the exact true/false result, not just truthiness
        result = subject.#{method_name}(input_value)
        expect(result).to eq(true).or eq(false)
      BODY
    end,
    "integer_literal" => build(it_desc: "returns the exact integer value from") do |method_name|
      <<~BODY
        # Assert the exact numeric value, not just > 0 or truthy
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "float_literal" => build(it_desc: "returns the exact float value from") do |method_name|
      <<~BODY
        # Assert the exact floating-point result
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "string_literal" => build(it_desc: "returns the exact string content from") do |method_name|
      <<~BODY
        # Assert the exact string value, not just presence or non-empty
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "symbol_literal" => build(it_desc: "returns the exact symbol from") do |method_name|
      <<~BODY
        # Assert the exact symbol value, not just that it is a Symbol
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "array_literal" => build(it_desc: "returns the expected array contents from") do |method_name|
      <<~BODY
        # Assert the exact array elements, not just non-empty or truthy
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "hash_literal" => build(it_desc: "returns the expected hash contents from") do |method_name|
      <<~BODY
        # Assert the exact keys and values, not just non-empty or truthy
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "collection_replacement" => build(it_desc: "uses the return value of the collection operation in") do |method_name|
      <<~BODY
        # Assert the return value of the collection method, not just side effects
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "conditional_negation" => build(it_desc: "exercises both branches of the conditional in") do |method_name|
      <<~BODY
        # Test with inputs that make the condition true AND false
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "conditional_branch" => build(it_desc: "exercises the removed branch of the conditional in") do |method_name|
      <<~BODY
        # Test with inputs that trigger the branch removed by this mutation
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "statement_deletion" => build(it_desc: "depends on the side effect of the deleted statement in", action: :deleted) do |method_name|
      <<~BODY
        # Assert a side effect or return value that changes when this statement is removed
        subject.#{method_name}(input_value)
        expect(observable_side_effect).to eq(expected)
      BODY
    end,
    "method_body_replacement" => build(it_desc: "verifies the return value or side effects of") do |method_name|
      <<~BODY
        # Assert the method produces a meaningful result, not just nil
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "return_value_removal" => build(it_desc: "uses the return value of") do |method_name|
      <<~BODY
        # Assert the caller depends on the return value, not just side effects
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "method_call_removal" => build(it_desc: "depends on the return value or side effect of the call in") do |method_name|
      <<~BODY
        # Assert the method call's effect is observable
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "compound_assignment" => build(it_desc: "verifies the compound assignment side effect in") do |method_name|
      <<~BODY
        # Assert the accumulated value after the compound assignment
        # The mutation changes the operator, so the final value will differ
        subject.#{method_name}(input_value)
        expect(observable_side_effect).to eq(expected)
      BODY
    end,
    "nil_replacement" => build(it_desc: "asserts the nil return value from") do |method_name|
      <<~BODY
        # Assert the method returns nil, not a substituted value
        result = subject.#{method_name}(input_value)
        expect(result).to be_nil
      BODY
    end,
    "superclass_removal" => build(it_desc: "depends on inherited behavior in", action: :removed_superclass) do |method_name|
      <<~BODY
        # Assert behavior that comes from the superclass
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "local_variable_assignment" => build(it_desc: "verifies the local variable assignment is used in") do |method_name|
      <<~BODY
        # Assert that the assigned variable is read later, not just the value expression
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "instance_variable_write" => build(it_desc: "verifies the instance variable @state is set correctly in") do |method_name|
      <<~BODY
        # Assert that the instance variable holds the expected value after the method runs
        subject.#{method_name}(input_value)
        expect(subject.instance_variable_get(:@variable)).to eq(expected)
      BODY
    end,
    "class_variable_write" => build(it_desc: "verifies the class variable @@shared state is set correctly in") do |method_name|
      <<~BODY
        # Assert that the class variable holds the expected value and affects shared state
        subject.#{method_name}(input_value)
        expect(described_class.class_variable_get(:@@variable)).to eq(expected)
      BODY
    end,
    "global_variable_write" => build(it_desc: "verifies the global variable $state is set correctly in") do |method_name|
      <<~BODY
        # Assert that the global variable holds the expected value after the method runs
        subject.#{method_name}(input_value)
        expect($variable).to eq(expected)
      BODY
    end,
    "mixin_removal" => build(it_desc: "depends on behavior from the included module in", action: :removed) do |method_name|
      <<~BODY
        # Assert behavior provided by the mixin
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "rescue_removal" => build(it_desc: "verifies the rescue handler is needed in", action: :removed) do |method_name|
      <<~BODY
        # Trigger the rescued exception and assert the handler's effect
        result = subject.#{method_name}(input_that_raises)
        expect(result).to eq(expected)
      BODY
    end,
    "rescue_body_replacement" => build(it_desc: "verifies the rescue handler produces the correct result in") do |method_name|
      <<~BODY
        # Trigger the exception and assert the rescue body's return value or side effect
        result = subject.#{method_name}(input_that_raises)
        expect(result).to eq(expected)
      BODY
    end,
    "inline_rescue" => build(it_desc: "verifies the inline rescue fallback value in") do |method_name|
      <<~BODY
        # Trigger the exception and assert the fallback value is correct
        result = subject.#{method_name}(input_that_raises)
        expect(result).to eq(expected)
      BODY
    end,
    "ensure_removal" => build(it_desc: "verifies the ensure cleanup runs in", action: :removed_ensure) do |method_name|
      <<~BODY
        # Assert that the cleanup side effect is observable after the method runs
        subject.#{method_name}(input_value)
        expect(observable_cleanup_effect).to eq(expected)
      BODY
    end,
    "break_statement" => build(it_desc: "verifies the break exits the loop correctly in") do |method_name|
      <<~BODY
        # Assert the loop exits early and returns the expected value
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "next_statement" => build(it_desc: "verifies the next skips the iteration correctly in") do |method_name|
      <<~BODY
        # Assert the iteration is skipped and the expected value is yielded
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "redo_statement" => build(it_desc: "verifies the redo retry logic is necessary in") do |method_name|
      <<~BODY
        # Assert the iteration restart changes the outcome
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "bitwise_replacement" => build(it_desc: "verifies the exact bitwise result in") do |method_name|
      <<~BODY
        # Assert the exact bit-level result to distinguish &, |, and ^ operators
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "bitwise_complement" => build(it_desc: "verifies the bitwise complement result in") do |method_name|
      <<~BODY
        # Assert the exact complement (~) value, not just sign or magnitude
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "bang_method" => build(it_desc: "verifies in-place vs copy semantics matter in") do |method_name|
      <<~BODY
        # Assert that the original object is or is not modified
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "zsuper_removal" => build(it_desc: "verifies inherited behavior from super is needed in") do |method_name|
      <<~BODY
        # Assert that the result depends on the superclass implementation
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "explicit_super_mutation" => build(it_desc: "verifies the correct arguments are passed to super in") do |method_name|
      <<~BODY
        # Assert the inherited method receives the expected arguments
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "index_to_fetch" => build(it_desc: "distinguishes [] from .fetch for missing keys in") do |method_name|
      <<~BODY
        # Access a missing key: [] returns nil, .fetch raises KeyError
        expect { subject.#{method_name}(collection_with_missing_key) }.to raise_error(KeyError)
      BODY
    end,
    "index_to_dig" => build(it_desc: "verifies the chained [] access returns the correct nested value in") do |method_name|
      <<~BODY
        # Assert the nested lookup produces the expected value
        result = subject.#{method_name}(nested_collection)
        expect(result).to eq(expected)
      BODY
    end,
    "index_assignment_removal" => build(it_desc: "verifies the []= assignment modifies the collection in") do |method_name|
      <<~BODY
        # Assert the collection contains the assigned value after the method runs
        result = subject.#{method_name}(collection)
        expect(result).to include(expected_key => expected_value)
      BODY
    end,
    "pattern_matching_guard" => build(it_desc: "verifies the pattern guard filters correctly in") do |method_name|
      <<~BODY
        # Test with input that matches the pattern but fails the guard condition
        # The guard should prevent matching, routing to a different branch
        result = subject.#{method_name}(input_matching_pattern_but_failing_guard)
        expect(result).to eq(expected)
      BODY
    end,
    "pattern_matching_alternative" => build(it_desc: "verifies each pattern alternative is reachable in") do |method_name|
      <<~BODY
        # Test with input that matches only one specific alternative
        # Each alternative should have a dedicated test case
        result = subject.#{method_name}(input_for_specific_alternative)
        expect(result).to eq(expected)
      BODY
    end,
    "collection_return" => build(it_desc: "returns a non-empty collection from") do |method_name|
      <<~BODY
        # Assert the collection has the expected elements, not just non-empty
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "scalar_return" => build(it_desc: "returns a non-zero/non-empty value from") do |method_name|
      <<~BODY
        # Assert the exact scalar value, not just presence or type
        result = subject.#{method_name}(input_value)
        expect(result).to eq(expected)
      BODY
    end,
    "pattern_matching_array" => build(it_desc: "verifies each array pattern element matters in") do |method_name|
      <<~BODY
        # Test with input where changing one element type causes a different match
        # Each position in the array pattern should be validated
        result = subject.#{method_name}(input_with_wrong_element_type)
        expect(result).to eq(expected)
      BODY
    end
  }.freeze
end
