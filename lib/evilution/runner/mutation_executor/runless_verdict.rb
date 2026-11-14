# frozen_string_literal: true

require_relative "../mutation_executor"
require_relative "../../result/mutation_result"

# The verdict a mutation gets without a test run, when one can be given:
# its mutated source does not parse, or no test executes a line it sits on
# (asked of `coverage`, an integration backed by a coverage map). nil for
# every other mutation, which runs.
#
# A mutation no test executes could only survive, and a survivor costs the
# most of any verdict: the whole resolved spec file, then a confirmation run.
class Evilution::Runner::MutationExecutor::RunlessVerdict
  def initialize(coverage: nil)
    @coverage = coverage
  end

  def call(mutation)
    return result(mutation, :unparseable) if mutation.unparseable?
    return result(mutation, :uncovered) if !@coverage.nil? && @coverage.uncovered?(mutation)

    nil
  end

  private

  def result(mutation, status)
    Evilution::Result::MutationResult.new(mutation: mutation, status: status)
  end
end
