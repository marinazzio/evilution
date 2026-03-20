# frozen_string_literal: true

module Evilution
  module Equivalent
    module Heuristic
      class NoopSource
        def match?(mutation)
          mutation.original_source == mutation.mutated_source
        end
      end
    end
  end
end
