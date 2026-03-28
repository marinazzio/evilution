# frozen_string_literal: true

class Evilution::Equivalent::Heuristic::NoopSource
  def match?(mutation)
    mutation.original_source == mutation.mutated_source
  end
end
