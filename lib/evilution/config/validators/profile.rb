# frozen_string_literal: true

require_relative "base"

class Evilution::Config::Validators::Profile < Evilution::Config::Validators::Base
  ALLOWED = %i[default strict].freeze

  def self.call(value)
    coerce_symbol!(value, allowed: ALLOWED, name: "profile")
  end
end
