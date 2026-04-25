# frozen_string_literal: true

require_relative "../../../result/mutation_result"

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass
class Evilution::Runner::MutationExecutor; end unless defined?(Evilution::Runner::MutationExecutor) # rubocop:disable Lint/EmptyClass
module Evilution::Runner::MutationExecutor::Neutralizer; end unless defined?(Evilution::Runner::MutationExecutor::Neutralizer)

# Reclassify results as :neutral when the failure was caused by test
# infrastructure rather than by the mutation. Two independent paths:
#
# 1) :error from a missing require / spec_helper / rails_helper / spec/support
#    initialization — detected by error_class ∈ INFRA_ERROR_CLASSES and
#    first backtrace frame matching INFRA_BACKTRACE_PATHS. Origin-only match
#    (not `any?`): Ruby backtraces typically carry spec_helper frames below
#    mutation-caused errors, so matching any frame would misclassify real
#    mutation NameError/LoadError as :neutral.
#
# 2) :killed from a CrashDetector test_crashed whose sole crash class is in
#    INFRA_CRASH_CLASSES (ActiveRecord::StatementTimeout, Timeout::Error,
#    etc.). These surface under parallel workers sharing a DB file or on a
#    slow CI; fork.rb initially reports them as :killed, and without this
#    demotion the kill count inflates with infra noise. No backtrace check:
#    the single-class signal from CrashDetector already rules out mixed
#    mutation-caused failures. See EV-toid / GH #814.
class Evilution::Runner::MutationExecutor::Neutralizer::InfraError
  INFRA_ERROR_CLASSES = %w[LoadError NameError].freeze
  INFRA_BACKTRACE_PATHS = %r{(?:^|/)(?:spec_helper\.rb|rails_helper\.rb|spec/support/)}
  INFRA_CRASH_CLASSES = %w[
    Timeout::Error
    ActiveRecord::StatementTimeout
    ActiveRecord::Deadlocked
    ActiveRecord::ConnectionTimeoutError
    ActiveRecord::LockWaitTimeout
    SQLite3::BusyException
  ].freeze
  private_constant :INFRA_ERROR_CLASSES, :INFRA_BACKTRACE_PATHS, :INFRA_CRASH_CLASSES

  def call(result, **_ctx)
    return neutralize(result) if infra_crash?(result)
    return result unless result.error?
    return result unless INFRA_ERROR_CLASSES.include?(result.error_class)
    return result unless infra_origin?(result.error_backtrace)

    neutralize(result)
  end

  private

  def infra_crash?(result)
    result.killed? && INFRA_CRASH_CLASSES.include?(result.error_class)
  end

  def infra_origin?(backtrace)
    frames = Array(backtrace)
    return false if frames.empty?

    frames.first =~ INFRA_BACKTRACE_PATHS ? true : false
  end

  def neutralize(result)
    Evilution::Result::MutationResult.new(
      mutation: result.mutation,
      status: :neutral,
      duration: result.duration,
      test_command: result.test_command,
      child_rss_kb: result.child_rss_kb,
      memory_delta_kb: result.memory_delta_kb,
      parent_rss_kb: result.parent_rss_kb,
      error_message: result.error_message,
      error_class: result.error_class,
      error_backtrace: result.error_backtrace
    )
  end
end
