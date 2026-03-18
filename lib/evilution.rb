# frozen_string_literal: true

require_relative "evilution/version"
require_relative "evilution/config"
require_relative "evilution/subject"
require_relative "evilution/mutation"
require_relative "evilution/ast/source_surgeon"
require_relative "evilution/ast/parser"
require_relative "evilution/mutator/base"
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
require_relative "evilution/mutator/registry"
require_relative "evilution/isolation/fork"
require_relative "evilution/isolation/in_process"
require_relative "evilution/parallel/pool"
require_relative "evilution/diff/parser"
require_relative "evilution/diff/file_filter"
require_relative "evilution/git/changed_files"
require_relative "evilution/integration/base"
require_relative "evilution/integration/rspec"
require_relative "evilution/result/mutation_result"
require_relative "evilution/result/summary"
require_relative "evilution/reporter/json"
require_relative "evilution/reporter/cli"
require_relative "evilution/reporter/suggestion"
require_relative "evilution/coverage/collector"
require_relative "evilution/coverage/test_map"
require_relative "evilution/spec_resolver"
require_relative "evilution/baseline"
require_relative "evilution/cli"
require_relative "evilution/runner"

module Evilution
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
