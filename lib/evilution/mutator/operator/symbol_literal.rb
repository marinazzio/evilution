# frozen_string_literal: true

require_relative "../operator"
require_relative "../../ast/round_half_mode"

class Evilution::Mutator::Operator::SymbolLiteral < Evilution::Mutator::Base
  extend Evilution::Mutator::ConstantValueSubjects

  def call(subject, filter: nil)
    @round_half_modes = []
    super
  end

  # The tie-breaking mode of `round` (`half: :even`) is left to
  # RoundHalfModeSwap: a made-up symbol there only raises, and nil rounds
  # like `:up`.
  def visit_call_node(node)
    mode = Evilution::AST::RoundHalfMode.of(node)
    @round_half_modes << mode if mode
    super
  end

  def visit_symbol_node(node)
    return super if label_form?(node) || round_half_mode?(node)

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: ":__evilution_mutated__",
      node: node
    )

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "nil",
      node: node
    )

    super
  end

  # An interpolated symbol (`:"visit_#{type}"`) as a whole. A label key
  # (`"a#{x}": 1`) cannot be replaced by a value, and a word of `%I[]` has no
  # quotes of its own: `nil` there would be the symbol `:nil`.
  def visit_interpolated_symbol_node(node)
    return super if node.opening_loc.nil? || label_form?(node)

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: ':""',
      node: node
    )

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "nil",
      node: node
    )

    super
  end

  private

  def round_half_mode?(node)
    @round_half_modes.any? { |mode| mode.equal?(node) }
  end

  # `a:` closes with `:`, a quoted label (`"a b":`) with `":`.
  def label_form?(node)
    closing = node.closing_loc
    !closing.nil? && closing.slice.end_with?(":")
  end
end
