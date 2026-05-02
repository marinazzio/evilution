# frozen_string_literal: true

require_relative "base"

class Evilution::Config::Validators::Profile < Evilution::Config::Validators::Base
  ALLOWED = %i[default strict].freeze
  MESSAGE = "profile must be default or strict"

  def self.call(value)
    raise Evilution::ConfigError, "#{MESSAGE}, got nil" if value.nil?

    raise Evilution::ConfigError, "#{MESSAGE}, got #{value.inspect}" unless value.is_a?(String) || value.is_a?(Symbol)

    sym = value.to_sym
    return sym if ALLOWED.include?(sym)

    raise Evilution::ConfigError, "#{MESSAGE}, got #{sym.inspect}"
  end
end
