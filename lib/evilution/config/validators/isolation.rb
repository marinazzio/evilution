# frozen_string_literal: true

require_relative "base"

class Evilution::Config::Validators::Isolation < Evilution::Config::Validators::Base
  ALLOWED = %i[auto fork in_process].freeze
  MESSAGE = "isolation must be auto, fork, or in_process"

  def self.call(value)
    raise Evilution::ConfigError, "#{MESSAGE}, got nil" if value.nil?

    raise Evilution::ConfigError, "#{MESSAGE}, got #{value.inspect}" unless value.is_a?(String) || value.is_a?(Symbol)

    sym = value.to_sym
    return sym if ALLOWED.include?(sym)

    raise Evilution::ConfigError, "#{MESSAGE}, got #{sym.inspect}"
  end
end
