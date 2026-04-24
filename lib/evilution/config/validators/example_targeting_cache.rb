# frozen_string_literal: true

require_relative "base"

class Evilution::Config::Validators::ExampleTargetingCache < Evilution::Config::Validators::Base
  def self.call(value)
    raise Evilution::ConfigError, "example_targeting_cache must be a Hash, got #{value.class}" unless value.is_a?(Hash)

    normalized = normalize_keys(value)
    merged = Evilution::Config::DEFAULTS[:example_targeting_cache].merge(normalized)
    require_positive_int!(merged, :max_files)
    require_positive_int!(merged, :max_blocks)
    merged
  end

  class << self
    private

    def normalize_keys(value)
      value.each_with_object({}) do |(k, v), acc|
        unless k.is_a?(String) || k.is_a?(Symbol)
          raise Evilution::ConfigError,
                "example_targeting_cache keys must be Strings or Symbols, got #{k.inspect}"
        end
        acc[k.to_sym] = v
      end
    end

    def require_positive_int!(cache, key)
      v = cache[key]
      return if v.is_a?(Integer) && v >= 1

      raise Evilution::ConfigError,
            "example_targeting_cache.#{key} must be a positive integer, got #{v.inspect}"
    end
  end
end
