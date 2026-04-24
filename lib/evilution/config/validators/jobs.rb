# frozen_string_literal: true

require_relative "base"

class Evilution::Config::Validators::Jobs < Evilution::Config::Validators::Base
  def self.call(value)
    coerce_positive_int!(value, name: "jobs")
  end
end
