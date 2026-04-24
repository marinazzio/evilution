# frozen_string_literal: true

require_relative "../builders"
require_relative "spec_resolver"
require_relative "../../spec_selector"

class Evilution::Config::Builders::SpecSelector
  def self.call(spec_files:, spec_mappings:, spec_pattern:, integration:)
    Evilution::SpecSelector.new(
      spec_files: spec_files,
      spec_mappings: spec_mappings,
      spec_pattern: spec_pattern,
      spec_resolver: Evilution::Config::Builders::SpecResolver.call(integration: integration)
    )
  end
end
