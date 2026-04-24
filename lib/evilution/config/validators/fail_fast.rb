# frozen_string_literal: true

require_relative "base"

class Evilution::Config::Validators::FailFast < Evilution::Config::Validators::Base
  def self.call(value)
    return nil if value.nil?

    coerce_positive_int!(value, name: "fail_fast")
  end
end
