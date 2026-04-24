# frozen_string_literal: true

require_relative "base"

class Evilution::Config::Validators::SpecPattern < Evilution::Config::Validators::Base
  def self.call(value)
    return nil if value.nil?
    return value if value.is_a?(String)

    raise Evilution::ConfigError, "spec_pattern must be nil or a String glob, got #{value.class}"
  end
end
