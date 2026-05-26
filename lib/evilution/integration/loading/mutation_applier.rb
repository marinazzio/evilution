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
    mark_feature_loaded(mutation.file_path)
    @redefinition_recovery.call(mutation.original_source) do
      @source_evaluator.call(eval_target, mutation.file_path)
    end
  end

  # The mutated source is eval'd straight into the VM — `eval` does not register
  # a `$LOADED_FEATURES` entry. Any later `require`/`require_relative` of the
  # same file then reloads the ORIGINAL from disk and clobbers the mutation, so
  # every mutation silently survives. Two paths trigger that reload:
  #   - the spec `require`s the file (it lazy-loads it and only the test
  #     references it);
  #   - the mutated source's OWN body `require_relative`s a sibling whose body
  #     `require_relative`s this file back (e.g. lib/evilution/mcp/*.rb tools).
  # The second reload happens DURING the eval, so registration must precede it:
  # `mark_feature_loaded` runs before `@source_evaluator.call`, not after. Under
  # fork isolation each worker starts from the same pre-`require` snapshot, so
  # without this the whole file scores 0%.
  def mark_feature_loaded(file_path)
    # When the isolator has chdir'd into a per-mutation sandbox (EV-wqxu /
    # GH #1278), anchor against PROJECT_ROOT so File.realpath does not chase
    # file_path into a non-existent /tmp path.
    base = Evilution.in_isolated_worker? ? Evilution::PROJECT_ROOT : Dir.pwd
    absolute = File.realpath(File.expand_path(file_path, base))
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
