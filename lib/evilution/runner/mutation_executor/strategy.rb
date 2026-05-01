# frozen_string_literal: true

require_relative "../mutation_executor"

# Namespace for MutationExecutor's execution strategies (Sequential, Parallel).
# Concrete strategy classes live in strategy/{sequential,parallel}.rb and are
# autoloaded on first reference.
module Evilution::Runner::MutationExecutor::Strategy
  autoload :Sequential, File.expand_path("strategy/sequential", __dir__)
  autoload :Parallel, File.expand_path("strategy/parallel", __dir__)
end
