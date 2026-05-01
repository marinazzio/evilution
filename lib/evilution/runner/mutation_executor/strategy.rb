# frozen_string_literal: true

require_relative "../mutation_executor"

# Namespace for MutationExecutor's execution strategies (Sequential, Parallel).
# Concrete strategy classes live in strategy/{sequential,parallel}.rb.
module Evilution::Runner::MutationExecutor::Strategy
end
