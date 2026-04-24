# frozen_string_literal: true

require_relative "base"

class Evilution::Config::Validators::Integration < Evilution::Config::Validators::Base
  ALLOWED = %i[rspec minitest].freeze

  def self.call(value)
    coerce_symbol!(value, allowed: ALLOWED, name: "integration")
  end
end
