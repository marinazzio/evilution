# frozen_string_literal: true

require_relative "spec_resolver"

class Evilution::SpecSelector
  def initialize(spec_files: [], spec_mappings: {}, spec_pattern: nil, spec_resolver: Evilution::SpecResolver.new)
    @spec_files = Array(spec_files)
    @spec_mappings = spec_mappings || {}
    @spec_pattern = spec_pattern
    @spec_resolver = spec_resolver
  end

  def call(source_path)
    return @spec_files unless @spec_files.empty?

    mapped = mapping_for(source_path)
    if mapped
      existing = mapped.select { |path| project_relative_exists?(path) }
      return existing unless existing.empty?
    end

    resolved = resolve_via_resolver(source_path)
    resolved && !resolved.empty? ? resolved : nil
  end

  private

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

  # Same semantics as Evilution::SpecResolver#project_relative_exists?
  def project_relative_exists?(path)
    return true if File.exist?(path)
    return false unless Evilution.in_isolated_worker?

    File.exist?(File.expand_path(path, Evilution::PROJECT_ROOT))
  end
end
