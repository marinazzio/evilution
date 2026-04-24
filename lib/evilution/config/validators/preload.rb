# frozen_string_literal: true

require_relative "base"

class Evilution::Config::Validators::Preload < Evilution::Config::Validators::Base
  def self.call(value)
    return nil if value.nil?
    return false if value == false
    return value if value.is_a?(String)

    raise Evilution::ConfigError, "preload must be nil, false, or a String path, got #{value.inspect}"
  end
end
