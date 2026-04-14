# frozen_string_literal: true

class Evilution::CLI
  Result = Struct.new(:exit_code, :error, :error_rendered, keyword_init: true) do
    def initialize(exit_code:, error: nil, error_rendered: false)
      super
    end
  end
end
