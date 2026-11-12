# frozen_string_literal: true

require_relative "spec_resolver"

class Evilution::SpecSelector
  def initialize(spec_files: [], spec_mappings: {}, spec_pattern: nil, spec_resolver: Evilution::SpecResolver.new)
    @spec_files = Array(spec_files)
    @spec_mappings = spec_mappings || {}
    @spec_pattern = spec_pattern
    @spec_resolver = spec_resolver
    @resolved = {}
  end

  # Answers are remembered per source for the life of this selector, because
  # the integrations ask once per mutation and the resolver may read every
  # sibling test to rank them. A selector belongs to one run (it is built with
  # the run's Config), so a long-running process such as the MCP server never
  # reuses an answer across runs. The baseline resolves in the parent process
  # before any mutation fork, so forked workers inherit the warmed answers.
  def call(source_path)
    return @spec_files unless @spec_files.empty?
    return @resolved[source_path] if @resolved.key?(source_path)

    @resolved[source_path] = resolve(source_path)
  end

  private

  def resolve(source_path)
    mapped = mapping_for(source_path)
    if mapped
      existing = mapped.select { |path| Evilution::SpecResolver::ProjectFiles.exist?(path) }
      return existing.freeze unless existing.empty?
    end

    resolved = resolve_via_resolver(source_path)
    resolved && !resolved.empty? ? resolved.dup.freeze : nil
  end

  # Prefer the array-returning #resolve_specs, but fall back to the older single-file #call contract so a custom
  # resolver that only implements #call keeps working.
  def resolve_via_resolver(source_path)
    if @spec_resolver.respond_to?(:resolve_specs)
      @spec_resolver.resolve_specs(source_path, spec_pattern: @spec_pattern)
    else
      file = @spec_resolver.call(source_path, spec_pattern: @spec_pattern)
      file ? [file] : nil
    end
  end

  def mapping_for(source_path)
    @spec_mappings[normalize(source_path)]
  end

  def normalize(path)
    return path if path.nil?

    normalized = path.to_s
    if normalized.start_with?("/")
      normalized = normalized.delete_prefix("#{Dir.pwd}/")
      normalized = normalized.delete_prefix("#{Evilution::PROJECT_ROOT}/") if Evilution.in_isolated_worker?
    end
    normalized.delete_prefix("./")
  end
end
