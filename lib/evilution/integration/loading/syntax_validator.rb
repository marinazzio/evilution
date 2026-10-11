# frozen_string_literal: true

require_relative "../loading"
require_relative "../../ast/syntax_check"

class Evilution::Integration::Loading::SyntaxValidator
  ERROR_MESSAGE = "mutated source has syntax errors"

  def call(source)
    return nil if Evilution::AST::SyntaxCheck.valid?(source)

    {
      passed: false,
      error: ERROR_MESSAGE,
      error_class: "SyntaxError",
      error_backtrace: []
    }
  end
end
