# frozen_string_literal: true

require_relative "base"

class Evilution::Config::Validators::Hooks < Evilution::Config::Validators::Base
  def self.call(value)
    return {} if value.nil?
    raise Evilution::ConfigError, "hooks must be a mapping of event names to file paths, got #{value.class}" unless value.is_a?(Hash)

    value
  end
end
