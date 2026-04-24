# frozen_string_literal: true

require_relative "base"

class Evilution::Config::Validators::ExampleTargetingFallback < Evilution::Config::Validators::Base
  FALLBACKS = %i[full_file unresolved].freeze

  def self.call(value)
    unless value.is_a?(String) || value.is_a?(Symbol)
      raise Evilution::ConfigError,
            "example_targeting_fallback must be full_file or unresolved, got #{value.inspect}"
    end

    sym = value.to_sym
    unless FALLBACKS.include?(sym)
      raise Evilution::ConfigError,
            "example_targeting_fallback must be full_file or unresolved, got #{sym.inspect}"
    end

    sym
  end
end
