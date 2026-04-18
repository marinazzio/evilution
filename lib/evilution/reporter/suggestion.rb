# frozen_string_literal: true

require_relative "../reporter"

class Evilution::Reporter::Suggestion
  DEFAULT_SUGGESTION = "Add a more specific test that detects this mutation"

  def initialize(suggest_tests: false, integration: :rspec, registry: Registry.default)
    @suggest_tests = suggest_tests
    @integration = integration
    @registry = registry
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
    op = mutation.operator_name
    if @suggest_tests
      concrete = @registry.concrete(op, integration: @integration)
      return concrete.call(mutation) if concrete
    end

    @registry.generic(op) || DEFAULT_SUGGESTION
  end
end

require_relative "suggestion/diff_helpers"
require_relative "suggestion/registry"
