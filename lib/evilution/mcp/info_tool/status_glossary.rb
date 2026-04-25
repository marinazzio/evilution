# frozen_string_literal: true

require_relative "../info_tool"
require_relative "../../result/mutation_result"

module Evilution::MCP::InfoTool::StatusGlossary
  ENTRIES = [
    {
      "status" => "killed",
      "meaning" => "A test failed when the mutation was applied — the test suite caught the mutation. " \
                   "This is the desired outcome.",
      "counted_in_score" => true
    },
    {
      "status" => "survived",
      "meaning" => "No test failed when the mutation was applied — gap in coverage. " \
                   "The test suite did not detect the behavioral change.",
      "counted_in_score" => true
    },
    {
      "status" => "timeout",
      "meaning" => "Test run exceeded the configured per-mutation timeout. " \
                   "Treated like survived for scoring (counted in the denominator); " \
                   "may indicate an infinite loop introduced by the mutation.",
      "counted_in_score" => true
    },
    {
      "status" => "error",
      "meaning" => "Mutation execution raised an unexpected error (syntax error at load time, " \
                   "boot failure, test-infrastructure crash). The mutation could not be evaluated.",
      "counted_in_score" => false
    },
    {
      "status" => "neutral",
      "meaning" => "Baseline tests already failed before the mutation was applied — pre-existing " \
                   "test-suite problem (flaky spec, infra collision, fixture setup failure). " \
                   "Not a meaningful mutation signal.",
      "counted_in_score" => false
    },
    {
      "status" => "equivalent",
      "meaning" => "Mutation is provably identical to the original source " \
                   "(e.g. a no-op replacement that the parser or evaluator treats as semantically equal).",
      "counted_in_score" => false
    },
    {
      "status" => "unresolved",
      "meaning" => "No spec/test file resolved for the mutated source — coverage gap, not a failure. " \
                   "The file has no corresponding test file the resolver could locate.",
      "counted_in_score" => false
    },
    {
      "status" => "unparseable",
      "meaning" => "Mutated source failed to parse (e.g. dangling heredoc after method_body_replacement). " \
                   "Short-circuited before execution; no test run was attempted.",
      "counted_in_score" => false
    }
  ].freeze

  module_function

  def entries
    check_drift!
    ENTRIES
  end

  def check_drift!
    defined    = Evilution::Result::MutationResult::STATUSES.map(&:to_s).sort
    documented = ENTRIES.map { |s| s["status"] }.sort
    return if defined == documented

    missing = (defined - documented) + (documented - defined)
    raise Evilution::Error, "status glossary drift: #{missing.inspect}"
  end
end
