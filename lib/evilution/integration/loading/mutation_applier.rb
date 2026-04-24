# frozen_string_literal: true

require_relative "../loading"
require_relative "syntax_validator"
require_relative "constant_pinner"
require_relative "concern_state_cleaner"
require_relative "source_evaluator"
require_relative "redefinition_recovery"

# Composes the load-time pipeline that applies a mutation's new source to the
# running VM: syntax-validate -> pin top-level constants (beats Zeitwerk) ->
# clear AS::Concern state -> eval inside a redefinition-recovery wrapper.
# Returns nil on success or a failure-shaped hash on any error.
class Evilution::Integration::Loading::MutationApplier
  def initialize(syntax_validator: Evilution::Integration::Loading::SyntaxValidator.new,
                 constant_pinner: Evilution::Integration::Loading::ConstantPinner.new,
                 concern_state_cleaner: Evilution::Integration::Loading::ConcernStateCleaner.new,
                 source_evaluator: Evilution::Integration::Loading::SourceEvaluator.new,
                 redefinition_recovery: Evilution::Integration::Loading::RedefinitionRecovery.new)
    @syntax_validator = syntax_validator
    @constant_pinner = constant_pinner
    @concern_state_cleaner = concern_state_cleaner
    @source_evaluator = source_evaluator
    @redefinition_recovery = redefinition_recovery
  end

  def call(mutation)
    syntax_error = @syntax_validator.call(mutation.mutated_source)
    return syntax_error if syntax_error

    @constant_pinner.call(mutation.original_source)
    @concern_state_cleaner.call(mutation.file_path)
    @redefinition_recovery.call(mutation.original_source) do
      @source_evaluator.call(mutation.mutated_source, mutation.file_path)
    end
    nil
  rescue SyntaxError => e
    {
      passed: false,
      error: "syntax error in mutated source: #{e.message}",
      error_class: e.class.name,
      error_backtrace: Array(e.backtrace).first(5)
    }
  rescue ScriptError, StandardError => e
    {
      passed: false,
      error: "#{e.class}: #{e.message}",
      error_class: e.class.name,
      error_backtrace: Array(e.backtrace).first(5)
    }
  end
end
