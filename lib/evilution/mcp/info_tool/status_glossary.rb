# frozen_string_literal: true

require_relative "../info_tool"
require_relative "../../result/mutation_result"

module Evilution::MCP::InfoTool::StatusGlossary
  ENTRIES = [
    {
      "status" => "killed",
      "meaning" => "A test failed when the mutation was applied — the test suite caught the mutation. " \
                   "This is the desired outcome. Also a mutation that made its own file raise while loading, " \
                   "before any test ran, when the original file still loads (error_message starts with " \
                   "'load failed:'), and one whose test process died on an exception no handler saw while " \
                   "the tests ran, as a crashing test would (error_message starts with 'child died' under " \
                   "fork isolation, 'test run ended by' under in-process isolation).",
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
                   "boot failure, test-infrastructure crash). The mutation could not be evaluated. " \
                   "Includes a test process that died on an unhandled exception before the tests ran " \
                   "('child died ... before the tests ran'; error_class is the exception's own class), and " \
                   "results that are no verdict on the mutation at all: a fork child's result that " \
                   "was unreadable, a worker's result that could not be read (the worker was replaced), " \
                   "a child that died on a signal without writing a result (SIGABRT: the Ruby VM aborted; " \
                   "SIGSEGV; SIGKILL, e.g. out of memory). Re-run that one mutation; if a VM abort repeats, " \
                   "the mutant crashes the interpreter.",
      "counted_in_score" => false
    },
    {
      "status" => "neutral",
      "meaning" => "No verdict: the tests failed only on examples that were already failing before " \
                   "the mutation was applied, or the test process crashed on infrastructure. " \
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
  ].each(&:freeze).freeze

  module_function

  def entries
    check_drift!
    ENTRIES
  end

  def check_drift!
    defined_statuses = Evilution::Result::MutationResult::STATUSES.map(&:to_s).sort
    documented = ENTRIES.map { |s| s["status"] }.sort
    return if defined_statuses == documented

    missing = (defined_statuses - documented) + (documented - defined_statuses)
    raise Evilution::Error, "status glossary drift: #{missing.inspect}"
  end
end
