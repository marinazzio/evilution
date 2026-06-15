# frozen_string_literal: true

require_relative "base"

class Evilution::Config::Validators::ExampleTargetingStrategy < Evilution::Config::Validators::Base
  STRATEGIES = %i[lexical coverage].freeze

  def self.call(value)
    unless value.is_a?(String) || value.is_a?(Symbol)
      raise Evilution::ConfigError,
            "example_targeting_strategy must be lexical or coverage, got #{value.inspect}"
    end

    sym = value.to_sym
    unless STRATEGIES.include?(sym)
      raise Evilution::ConfigError,
            "example_targeting_strategy must be lexical or coverage, got #{sym.inspect}"
    end

    sym
  end
end
