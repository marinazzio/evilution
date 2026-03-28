# frozen_string_literal: true

require_relative "../heuristic"

class Evilution::Equivalent::Heuristic::NoopSource
  def match?(mutation)
    mutation.original_source == mutation.mutated_source
  end
end
