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
# The eval target is mutation.eval_source, which Mutator::Base pre-populates
# with the neutralized form (non-idempotent class-body calls replaced with
# `nil`). The neutralization itself happens once at mutation-generation time
# rather than per-iter — SyntaxValidator still runs Prism per mutation, but
# the extra neutralizer parse stays out of the hot path. Falls back to
# mutation.mutated_source when no pre-eval transform was attached.
# RedefinitionRecovery stays as a safety net for cases the neutralizer's
# allowlist heuristic misses. Returns nil on success or a failure-shaped
# hash on any error.
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
    eval_target = resolve_eval_target(mutation)
    syntax_error = @syntax_validator.call(eval_target)
    return syntax_error if syntax_error

    apply(mutation, eval_target)
    nil
  rescue SyntaxError => e
    failure_result(e, "syntax error in mutated source: #{e.message}")
  rescue ScriptError, StandardError => e
    failure_result(e, "#{e.class}: #{e.message}")
  end

  private

  def resolve_eval_target(mutation)
    return mutation.eval_source if mutation.respond_to?(:eval_source)

    mutation.mutated_source
  end

  def apply(mutation, eval_target)
    @constant_pinner.call(mutation.original_source)
    @concern_state_cleaner.call(mutation.file_path)
    @redefinition_recovery.call(mutation.original_source) do
      @source_evaluator.call(eval_target, mutation.file_path)
    end
    mark_feature_loaded(mutation.file_path)
  end

  # The mutated source is eval'd straight into the VM — `eval` does not register
  # a `$LOADED_FEATURES` entry. If the spec then `require`s the same file (common
  # when the project lazy-loads it and only the test references it), `require`
  # reloads the ORIGINAL from disk and clobbers the mutation, so every mutation
  # silently survives. Under fork isolation each worker starts from the same
  # pre-`require` snapshot, so the whole file scores 0%. Registering the
  # canonical path makes a later `require`/`require_relative` a no-op.
  def mark_feature_loaded(file_path)
    absolute = File.realpath(File.expand_path(file_path))
    $LOADED_FEATURES << absolute unless $LOADED_FEATURES.include?(absolute)
  rescue Errno::ENOENT
    nil
  end

  def failure_result(error, message)
    {
      passed: false,
      error: message,
      error_class: error.class.name,
      error_backtrace: Array(error.backtrace).first(5)
    }
  end
end
