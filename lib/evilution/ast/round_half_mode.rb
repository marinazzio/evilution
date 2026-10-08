# frozen_string_literal: true

require "prism"
require_relative "../ast"

# The tie-breaking mode of a `round` call: the `:even` of
# `amount.round(2, half: :even)`. Only a literal mode Ruby accepts counts; a
# mode held in a variable, `nil` or an unknown symbol is not one.
module Evilution::AST::RoundHalfMode
  MODES = %i[up even down].freeze

  # The symbol node holding the mode, or nil when node is not a `round` call
  # with a literal mode.
  def self.of(node)
    return nil unless node.is_a?(Prism::CallNode) && node.name == :round

    value = half_value(node.arguments)
    value if value.is_a?(Prism::SymbolNode) && MODES.include?(value.unescaped.to_sym)
  end

  # The value given to `half:`, whatever it is.
  def self.half_value(arguments)
    return nil unless arguments

    keywords = arguments.arguments.grep(Prism::KeywordHashNode).flat_map(&:elements)
    pair = keywords.find { |element| half_key?(element) }
    pair.value if pair
  end

  def self.half_key?(element)
    return false unless element.is_a?(Prism::AssocNode)

    key = element.key
    key.is_a?(Prism::SymbolNode) && key.unescaped == "half"
  end

  private_class_method :half_value, :half_key?
end
