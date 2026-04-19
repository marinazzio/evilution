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
      existing = mapped.select { |path| File.exist?(path) }
      return existing unless existing.empty?
    end

    resolved = @spec_resolver.call(source_path, spec_pattern: @spec_pattern)
    resolved ? [resolved] : nil
  end

  private

  def mapping_for(source_path)
    @spec_mappings[normalize(source_path)]
  end

  def normalize(path)
    return path if path.nil?

    path.to_s.delete_prefix("./")
  end
end
