# frozen_string_literal: true

require_relative "../mutate_tool"
require_relative "../../runner"
require_relative "../../spec_resolver"

module Evilution::MCP::MutateTool::SurvivedEnricher
  def self.call(data, survived_results, config)
    entries = data["survived"]
    return unless entries.is_a?(Array)

    explicit_spec, resolver = build_resolver(config)
    cache = {}

    entries.each_with_index do |entry, index|
      result = survived_results[index]
      next unless result

      enrich_entry(entry, result.mutation, explicit_spec, resolver, cache)
    end
  end

  def self.build_resolver(config)
    explicit_spec = explicit_spec_override(config)
    resolver = explicit_spec ? nil : resolver_for_integration(config.integration)
    [explicit_spec, resolver]
  end
  private_class_method :build_resolver

  def self.enrich_entry(entry, mutation, explicit_spec, resolver, cache)
    entry["subject"] = mutation.subject.name
    spec_file = explicit_spec || cache.fetch(mutation.file_path) do
      cache[mutation.file_path] = resolver.call(mutation.file_path)
    end
    entry["spec_file"] = spec_file if spec_file
    entry["next_step"] = build_next_step(mutation, spec_file)
  end
  private_class_method :enrich_entry

  def self.explicit_spec_override(config)
    return nil unless config.respond_to?(:spec_files)

    files = Array(config.spec_files).compact.map(&:to_s).reject(&:empty?)
    files.first
  end
  private_class_method :explicit_spec_override

  def self.resolver_for_integration(integration)
    integration_class = Evilution::Runner::INTEGRATIONS[integration.to_sym]
    return Evilution::SpecResolver.new unless integration_class

    integration_class.baseline_options[:spec_resolver] || Evilution::SpecResolver.new
  end
  private_class_method :resolver_for_integration

  def self.build_next_step(mutation, spec_file)
    target = spec_file || "the covering test file"
    "Add a test in #{target} that fails against this mutation at #{mutation.file_path}:#{mutation.line} " \
      "(#{mutation.subject.name}, #{mutation.operator_name})."
  end
  private_class_method :build_next_step
end
