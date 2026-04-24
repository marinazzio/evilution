# frozen_string_literal: true

require "prism"
require_relative "../loading"

class Evilution::Integration::Loading::SyntaxValidator
  ERROR_MESSAGE = "mutated source has syntax errors"

  def call(source)
    return nil if Prism.parse(source).success?

    {
      passed: false,
      error: ERROR_MESSAGE,
      error_class: "SyntaxError",
      error_backtrace: []
    }
  end
end
