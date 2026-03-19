# frozen_string_literal: true

module Evilution
  class SpecResolver
    STRIPPABLE_PREFIXES = %w[lib/ app/].freeze

    def call(source_path)
      return nil if source_path.nil? || source_path.empty?

      normalized = normalize_path(source_path)
      candidates = candidate_spec_paths(normalized)
      candidates.find { |path| File.exist?(path) }
    end

    def resolve_all(source_paths)
      Array(source_paths).filter_map { |path| call(path) }.uniq
    end

    private

    def normalize_path(path)
      path = path.delete_prefix("./")
      path = path.delete_prefix("#{Dir.pwd}/") if path.start_with?("/")
      path
    end

    def candidate_spec_paths(source_path)
      base = source_path.sub(/\.rb\z/, "_spec.rb")
      prefix = STRIPPABLE_PREFIXES.find { |p| source_path.start_with?(p) }

      candidates = if prefix
                     stripped = base.delete_prefix(prefix)
                     ["spec/#{stripped}", "spec/#{base}"]
                   else
                     ["spec/#{base}"]
                   end

      candidates + parent_fallback_candidates(candidates.first)
    end

    def parent_fallback_candidates(spec_path)
      parts = spec_path.split("/")
      # parts: ["spec", "models", "game", "round_spec.rb"]
      # We need at least 3 parts: "spec", a directory, and a file
      return [] if parts.length < 4

      candidates = []
      # Remove filename, then progressively remove directories
      dir_parts = parts[1..-2] # ["models", "game"]
      (dir_parts.length - 1).downto(0) do |i|
        file = "#{dir_parts[i]}_spec.rb"
        if i.zero?
          candidates << "spec/#{file}"
        else
          parent = dir_parts[0...i].join("/")
          candidates << "spec/#{parent}/#{file}"
        end
      end
      candidates
    end
  end
end
