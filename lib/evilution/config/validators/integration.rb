# frozen_string_literal: true

require_relative "base"

class Evilution::Config::Validators::Integration < Evilution::Config::Validators::Base
  ALLOWED = %i[rspec minitest test_unit].freeze

  # CLI users naturally write the gem name `test-unit`; the internal symbol
  # uses underscore form to match the file path and registry key. Normalize
  # hyphenated string input before coercion.
  def self.call(value)
    value = value.tr("-", "_") if value.is_a?(String)
    coerce_symbol!(value, allowed: ALLOWED, name: "integration")
  end
end
