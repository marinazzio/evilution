# frozen_string_literal: true

require_relative "../mutation_executor"

# Namespace for MutationExecutor's neutralization rules (InfraError,
# BaselineFailed). Concrete neutralizer classes live in neutralizer/*.rb and
# are autoloaded on first reference.
module Evilution::Runner::MutationExecutor::Neutralizer
  autoload :InfraError, File.expand_path("neutralizer/infra_error", __dir__)
  autoload :BaselineFailed, File.expand_path("neutralizer/baseline_failed", __dir__)
end
