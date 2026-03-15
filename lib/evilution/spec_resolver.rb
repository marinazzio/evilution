# frozen_string_literal: true

module Evilution
  class SpecResolver
    STRIPPABLE_PREFIXES = %w[lib/ app/].freeze

    def call(source_path)
      return nil if source_path.nil? || source_path.empty?

      candidates = candidate_spec_paths(source_path)
      candidates.find { |path| File.exist?(path) }
    end

    def resolve_all(source_paths)
      source_paths.filter_map { |path| call(path) }.uniq
    end

    private

    def candidate_spec_paths(source_path)
      base = source_path.sub(/\.rb\z/, "_spec.rb")
      prefix = STRIPPABLE_PREFIXES.find { |p| source_path.start_with?(p) }

      if prefix
        stripped = "spec/#{base.delete_prefix(prefix)}"
        kept = "spec/#{base}"
        [stripped, kept]
      else
        ["spec/#{base}"]
      end
    end
  end
end
