# frozen_string_literal: true

require_relative "../mutation_executor"

# One mutation's test run under the isolator, within its time limit.
#
# A run whose tests the integration tried in an order of its own (see
# Integration::Base#reorders?) and that timed out is run again in the defined
# order, and that run decides. The reordering may have started with the very
# test the mutant hangs, ahead of one that would have failed on it at once, so
# its timeout says nothing about what the defined order would have found.
class Evilution::Runner::MutationExecutor::IsolatedRun
  def initialize(isolator)
    @isolator = isolator
  end

  def call(mutation, integration, limit)
    reordered = reorders?(integration)
    result = isolate(mutation, integration, limit)
    result = integration.in_defined_order { isolate(mutation, integration, limit) } if reordered && result.timeout?
    result.timeout? ? result.with_time_limit(limit) : result
  end

  private

  # Asked before the run: the integration's answer is about the run to come.
  def reorders?(integration)
    integration.respond_to?(:reorders?) && integration.reorders?
  end

  def isolate(mutation, integration, limit)
    @isolator.call(mutation: mutation, test_command: ->(m) { integration.call(m) }, timeout: limit)
  end
end
