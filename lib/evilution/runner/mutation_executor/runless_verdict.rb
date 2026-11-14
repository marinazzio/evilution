# frozen_string_literal: true

require_relative "../mutation_executor"
require_relative "../../result/mutation_result"
require_relative "probe_first"

# The verdict a mutation gets without a test run, when one can be given:
# its mutated source does not parse, no test executes a line it sits on
# (asked of `coverage`, an integration backed by a coverage map), or its
# subject's sentinel survived (asked of `probe`, see ProbeFirst), which
# implies it survives too. nil for every other mutation, which runs.
#
# A mutation no test executes could only survive, and a survivor costs the
# most of any verdict: the whole resolved spec file, then a confirmation run.
class Evilution::Runner::MutationExecutor::RunlessVerdict
  def initialize(coverage: nil, probe: Evilution::Runner::MutationExecutor::ProbeFirst::NONE)
    @coverage = coverage
    @probe = probe
  end

  def call(mutation)
    return result(mutation, :unparseable) if mutation.unparseable?
    return result(mutation, :uncovered) if !@coverage.nil? && @coverage.uncovered?(mutation)

    implied(mutation, @probe.implied_by(mutation))
  end

  private

  def result(mutation, status)
    Evilution::Result::MutationResult.new(mutation: mutation, status: status)
  end

  def implied(mutation, sentinel_operator)
    return nil if sentinel_operator.nil?

    Evilution::Result::MutationResult.new(mutation: mutation, status: :survived, implied_by: sentinel_operator)
  end
end
