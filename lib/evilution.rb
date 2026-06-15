# frozen_string_literal: true

require_relative "evilution/version"
require_relative "evilution/memory"
require_relative "evilution/config"
require_relative "evilution/subject"
require_relative "evilution/result"
require_relative "evilution/mutation"
require_relative "evilution/ast"
require_relative "evilution/parallel"
require_relative "evilution/ast/source_surgeon"
require_relative "evilution/ast/parser"
require_relative "evilution/ast/inheritance_scanner"
require_relative "evilution/ast/pattern"
require_relative "evilution/ast/sorbet_sig_detector"
require_relative "evilution/ast/pattern/matcher"
require_relative "evilution/ast/pattern/parser"
require_relative "evilution/hooks"
require_relative "evilution/hooks/registry"
require_relative "evilution/hooks/loader"
require_relative "evilution/mutator"
require_relative "evilution/mutator/base"
require_relative "evilution/mutator/operator"
require_relative "evilution/mutator/operator/comparison_replacement"
require_relative "evilution/mutator/operator/boolean_literal_replacement"
require_relative "evilution/mutator/operator/integer_literal"
require_relative "evilution/mutator/operator/float_literal"
require_relative "evilution/mutator/operator/nil_replacement"
require_relative "evilution/mutator/operator/boolean_operator_replacement"
require_relative "evilution/mutator/operator/arithmetic_replacement"
require_relative "evilution/mutator/operator/string_literal"
require_relative "evilution/mutator/operator/array_literal"
require_relative "evilution/mutator/operator/hash_literal"
require_relative "evilution/mutator/operator/conditional_branch"
require_relative "evilution/mutator/operator/symbol_literal"
require_relative "evilution/mutator/operator/conditional_negation"
require_relative "evilution/mutator/operator/negation_insertion"
require_relative "evilution/mutator/operator/statement_deletion"
require_relative "evilution/mutator/operator/method_body_replacement"
require_relative "evilution/mutator/operator/return_value_removal"
require_relative "evilution/mutator/operator/collection_replacement"
require_relative "evilution/mutator/operator/method_call_removal"
require_relative "evilution/mutator/operator/argument_removal"
require_relative "evilution/mutator/operator/block_removal"
require_relative "evilution/mutator/operator/block_pass_removal"
require_relative "evilution/mutator/operator/conditional_flip"
require_relative "evilution/mutator/operator/range_replacement"
require_relative "evilution/mutator/operator/regexp_mutation"
require_relative "evilution/mutator/operator/regex_simplification"
require_relative "evilution/mutator/operator/receiver_replacement"
require_relative "evilution/mutator/operator/send_mutation"
require_relative "evilution/mutator/operator/argument_nil_substitution"
require_relative "evilution/mutator/operator/compound_assignment"
require_relative "evilution/mutator/operator/keyword_argument"
require_relative "evilution/mutator/operator/multiple_assignment"
require_relative "evilution/mutator/operator/mixin_removal"
require_relative "evilution/mutator/operator/superclass_removal"
require_relative "evilution/mutator/operator/local_variable_assignment"
require_relative "evilution/mutator/operator/instance_variable_write"
require_relative "evilution/mutator/operator/class_variable_write"
require_relative "evilution/mutator/operator/global_variable_write"
require_relative "evilution/mutator/operator/rescue_removal"
require_relative "evilution/mutator/operator/rescue_body_replacement"
require_relative "evilution/mutator/operator/inline_rescue"
require_relative "evilution/mutator/operator/ensure_removal"
require_relative "evilution/mutator/operator/break_statement"
require_relative "evilution/mutator/operator/next_statement"
require_relative "evilution/mutator/operator/redo_statement"
require_relative "evilution/mutator/operator/bang_method"
require_relative "evilution/mutator/operator/bitwise_replacement"
require_relative "evilution/mutator/operator/bitwise_complement"
require_relative "evilution/mutator/operator/zsuper_removal"
require_relative "evilution/mutator/operator/explicit_super_mutation"
require_relative "evilution/mutator/operator/index_to_at"
require_relative "evilution/mutator/operator/index_to_fetch"
require_relative "evilution/mutator/operator/index_to_dig"
require_relative "evilution/mutator/operator/index_assignment_removal"
require_relative "evilution/mutator/operator/pattern_matching_guard"
require_relative "evilution/mutator/operator/pattern_matching_alternative"
require_relative "evilution/mutator/operator/pattern_matching_array"
require_relative "evilution/mutator/operator/collection_return"
require_relative "evilution/mutator/operator/scalar_return"
require_relative "evilution/mutator/operator/yield_statement"
require_relative "evilution/mutator/operator/splat_operator"
require_relative "evilution/mutator/operator/defined_check"
require_relative "evilution/mutator/operator/regex_capture"
require_relative "evilution/mutator/operator/loop_flip"
require_relative "evilution/mutator/operator/string_interpolation"
require_relative "evilution/mutator/operator/retry_removal"
require_relative "evilution/mutator/operator/case_when"
require_relative "evilution/mutator/operator/predicate_replacement"
require_relative "evilution/mutator/operator/predicate_to_nil"
require_relative "evilution/mutator/operator/equality_to_identity"
require_relative "evilution/mutator/operator/lambda_body"
require_relative "evilution/mutator/operator/begin_unwrap"
require_relative "evilution/mutator/operator/block_param_removal"
require_relative "evilution/mutator/operator/last_expression_removal"
require_relative "evilution/mutator/operator/argument_method_call_replacement"
require_relative "evilution/mutator/registry"
require_relative "evilution/equivalent"
require_relative "evilution/equivalent/heuristic"
require_relative "evilution/equivalent/detector"
require_relative "evilution/process_supervisor"
require_relative "evilution/isolation"
require_relative "evilution/isolation/fork"
require_relative "evilution/isolation/in_process"
require_relative "evilution/parallel/pool"
require_relative "evilution/session"
require_relative "evilution/session/store"
require_relative "evilution/session/diff"
require_relative "evilution/git"
require_relative "evilution/git/changed_files"
require_relative "evilution/integration"
require_relative "evilution/integration/base"
require_relative "evilution/integration/rspec"
require_relative "evilution/integration/minitest"
require_relative "evilution/result/mutation_result"
require_relative "evilution/result/summary"
require_relative "evilution/reporter"
require_relative "evilution/reporter/json"
require_relative "evilution/reporter/cli"
require_relative "evilution/reporter/html"
require_relative "evilution/reporter/suggestion"
require_relative "evilution/reporter/progress_bar"
require_relative "evilution/spec_resolver"
require_relative "evilution/baseline"
require_relative "evilution/cache"
require_relative "evilution/cli"
require_relative "evilution/disable_comment"
require_relative "evilution/runner"

module Evilution
  # Captured at load time, before any isolator can chdir into a per-mutation
  # sandbox. Used as the anchor for resolving project-relative paths (spec
  # files, source files for eval) from inside a chdir'd child so the CWD
  # sandbox (EV-wqxu / GH #1278) cannot break spec resolution or eval __FILE__.
  PROJECT_ROOT = Dir.pwd.freeze unless defined?(PROJECT_ROOT)

  # Flag set by isolators (Evilution::Isolation::Fork in the forked child,
  # Evilution::Isolation::InProcess around the test_command) so spec
  # resolution and source eval anchor relative paths to PROJECT_ROOT instead
  # of Dir.pwd. Without this gate, a caller that intentionally chdirs to a
  # different project (e.g. a fixture layout in tests) would have its lookups
  # inadvertently fall back to the evilution dev tree.
  def self.in_isolated_worker!
    @in_isolated_worker = true
  end

  def self.in_isolated_worker?
    @in_isolated_worker == true
  end

  def self.with_isolated_worker
    previous = @in_isolated_worker
    @in_isolated_worker = true
    yield
  ensure
    @in_isolated_worker = previous
  end

  # Base directory for resolving project-relative paths. An isolated worker
  # has chdir'd into a per-mutation sandbox (EV-wqxu / GH #1278), so callers
  # in that context must anchor against PROJECT_ROOT rather than Dir.pwd —
  # otherwise spec files, source eval __FILE__, and $LOAD_PATH entries
  # resolve into the sandbox and break the run. In any other context (normal
  # use, tests that intentionally chdir into a fixture project layout, etc.)
  # the caller's Dir.pwd remains the truth.
  def self.project_base_dir
    in_isolated_worker? ? PROJECT_ROOT : Dir.pwd
  end

  class Error < StandardError
    attr_reader :file

    def initialize(message = nil, file: nil)
      super(message)
      @file = file
    end
  end

  class ConfigError < Error; end
  class ParseError < Error; end
  class IsolationError < Error; end
end
