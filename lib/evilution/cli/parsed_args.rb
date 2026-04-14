# frozen_string_literal: true

class Evilution::CLI
  ParsedArgs = Struct.new(
    :command, :options, :files, :line_ranges, :stdin_error, :parse_error,
    keyword_init: true
  ) do
    def initialize(command:, options: {}, files: [], line_ranges: {}, stdin_error: nil, parse_error: nil)
      super
    end
  end
end
