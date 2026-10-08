# frozen_string_literal: true

require_relative "../operator"
require_relative "../../ast/round_half_mode"

# Swap the tie-breaking mode of `round`: `amount.round(2, half: :even)`
# becomes `half: :up` and `half: :down`.
#
# The modes differ only for a value sitting exactly on a tie (`2.5`), so a
# survivor means no example rounds one — the case banker's rounding in money
# code exists for.
#
# Only a literal mode is swapped; one held in a variable is left alone.
# Integer, Float, Rational and BigDecimal all read `half:` the same way.
class Evilution::Mutator::Operator::RoundHalfModeSwap < Evilution::Mutator::Base
  def visit_call_node(node)
    mode = Evilution::AST::RoundHalfMode.of(node)
    swap(node, mode) if mode
    super
  end

  private

  def swap(node, mode)
    others = Evilution::AST::RoundHalfMode::MODES - [mode.unescaped.to_sym]

    others.each do |other|
      add_mutation(
        offset: mode.location.start_offset,
        length: mode.location.length,
        replacement: other.inspect,
        node: node
      )
    end
  end
end
