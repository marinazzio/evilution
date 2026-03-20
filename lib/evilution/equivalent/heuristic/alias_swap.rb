# frozen_string_literal: true

module Evilution
  module Equivalent
    module Heuristic
      class AliasSwap
        ALIAS_PAIRS = Set[
          Set[:detect, :find],
          Set[:length, :size],
          Set[:collect, :map]
        ].freeze

        def match?(mutation)
          return false unless mutation.operator_name == "send_mutation"

          diff = mutation.diff
          removed = extract_method(diff, "- ")
          added = extract_method(diff, "+ ")
          return false unless removed && added

          pair = Set[removed.to_sym, added.to_sym]
          ALIAS_PAIRS.include?(pair)
        end

        private

        def extract_method(diff, prefix)
          line = diff.split("\n").find { |l| l.start_with?(prefix) }
          return nil unless line

          match = line.match(/\.(\w+)(?:[\s(]|$)/)
          match && match[1]
        end
      end
    end
  end
end
