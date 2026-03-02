# frozen_string_literal: true

require_relative "evilution/version"
require_relative "evilution/config"
require_relative "evilution/subject"
require_relative "evilution/mutation"
require_relative "evilution/ast/source_surgeon"
require_relative "evilution/ast/parser"
require_relative "evilution/mutator/base"
require_relative "evilution/mutator/registry"
require_relative "evilution/mutator/operator/comparison_replacement"
require_relative "evilution/mutator/operator/boolean_literal_replacement"
require_relative "evilution/mutator/operator/integer_literal"
require_relative "evilution/mutator/operator/float_literal"
require_relative "evilution/mutator/operator/nil_replacement"
require_relative "evilution/mutator/operator/boolean_operator_replacement"
require_relative "evilution/mutator/operator/arithmetic_replacement"
require_relative "evilution/isolation/fork"
require_relative "evilution/integration/base"
require_relative "evilution/integration/rspec"
require_relative "evilution/result/mutation_result"
require_relative "evilution/result/summary"
require_relative "evilution/reporter/json"
require_relative "evilution/runner"

module Evilution
  class Error < StandardError; end
end
