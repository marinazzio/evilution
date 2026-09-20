# frozen_string_literal: true

require_relative "../neutralizer"
require_relative "../../../result/mutation_result"

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

  # Whether a crash class is one of the infrastructure failures that say
  # nothing about the mutation. The parallel strategy asks this before the
  # neutralisation pipeline has run, while the result is still a `:killed`
  # crash (EV-j0bv / GH #1607).
  def self.infra_crash_class?(error_class)
    INFRA_CRASH_CLASSES.include?(error_class)
  end

  # Whether this result is a kill that was demoted because the test process
  # crashed on infrastructure rather than on the mutation. Such a mutation got
  # no verdict, so a parallel run can re-run it once the contention is over.
  def self.infra_neutral?(result)
    result.neutral? && infra_crash_class?(result.error_class)
  end

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
      memory: result.memory,
      error: result.error
    )
  end
end
