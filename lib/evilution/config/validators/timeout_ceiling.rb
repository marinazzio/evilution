# frozen_string_literal: true

require_relative "../validators"
require_relative "base"

class Evilution::Config::Validators::TimeoutCeiling < Evilution::Config::Validators::Base
  def self.call(value)
    coerce_positive_number!(value, name: "timeout_ceiling")
  end
end
