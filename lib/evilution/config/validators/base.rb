# frozen_string_literal: true

require_relative "../validators"

class Evilution::Config::Validators::Base
  def self.call(_value)
    raise NotImplementedError
  end

  class << self
    private

    def coerce_symbol!(value, allowed:, name:)
      raise Evilution::ConfigError, "#{name} must be #{allowed.join(" or ")}, got nil" if value.nil?

      sym = value.to_sym
      return sym if allowed.include?(sym)

      raise Evilution::ConfigError, "#{name} must be #{allowed.join(" or ")}, got #{sym.inspect}"
    end

    def coerce_positive_int!(value, name:)
      raise Evilution::ConfigError, "#{name} must be a positive integer, got #{value.inspect}" if value.is_a?(Float)

      int = Integer(value)
      raise Evilution::ConfigError, "#{name} must be a positive integer, got #{int}" unless int >= 1

      int
    rescue ::ArgumentError, ::TypeError
      raise Evilution::ConfigError, "#{name} must be a positive integer, got #{value.inspect}"
    end
  end
end
