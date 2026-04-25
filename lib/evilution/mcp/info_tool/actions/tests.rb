# frozen_string_literal: true

require_relative "base"
require_relative "../config_factory"
require_relative "../../../runner"
require_relative "../../../spec_resolver"

class Evilution::MCP::InfoTool::Actions::Tests < Evilution::MCP::InfoTool::Actions::Base
  def self.call(files: nil, spec: nil, integration: nil, skip_config: nil, **)
    return config_error("files is required") if files.nil? || files.empty?

    config = Evilution::MCP::InfoTool::ConfigFactory.tests(
      files: files, spec: spec, integration: integration, skip_config: skip_config
    )
    return explicit_specs_response(files, config.spec_files) if config.spec_files.any?

    resolver = resolver_for(config.integration)
    resolved, unresolved = resolve_specs(files, resolver)
    success(
      "specs" => resolved,
      "unresolved" => unresolved,
      "total_sources" => files.length,
      "total_specs" => resolved.map { |r| r["spec"] }.uniq.length
    )
  end

  class << self
    private

    def resolver_for(integration)
      integration_class = Evilution::Runner::INTEGRATIONS[integration.to_sym]
      return Evilution::SpecResolver.new unless integration_class

      integration_class.baseline_options[:spec_resolver] || Evilution::SpecResolver.new
    end

    def explicit_specs_response(files, spec_files)
      success(
        "specs" => spec_files.map { |f| { "source" => nil, "spec" => f } },
        "unresolved" => [],
        "total_sources" => files.length,
        "total_specs" => spec_files.length
      )
    end

    def resolve_specs(files, resolver)
      resolved = []
      unresolved = []
      files.each do |source|
        found = resolver.call(source)
        if found
          resolved << { "source" => source, "spec" => found }
        else
          unresolved << source
        end
      end
      [resolved, unresolved]
    end
  end
end
