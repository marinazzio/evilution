# frozen_string_literal: true

require_relative "../operator"

# Replace a rational literal (`5r`, `1.5r`) with `0r`, `1r`, its two
# neighbours (`value + 1r`, `value - 1r`) and `nil`.
class Evilution::Mutator::Operator::RationalLiteral < Evilution::Mutator::Base
  def visit_rational_node(node)
    replacements_for(node.value).each { |value| add_mutation_with_replacement(node, literal_for(value)) }
    add_mutation_with_replacement(node, "nil")

    super
  end

  # A complex literal (`3ri`) is replaced as a whole by ComplexLiteral. Its
  # rational part is not a literal of its own: `nili` is not a value.
  def visit_imaginary_node(_node); end

  private

  def replacements_for(value)
    [0r, 1r, value + 1, value - 1].uniq - [value]
  end

  # A rational literal is an integer or a decimal, so its value and both
  # neighbours always have a finite decimal form.
  def literal_for(value)
    return "#{value.numerator}r" if value.denominator == 1

    digits = (1..).find { |count| ((10**count) % value.denominator).zero? }
    whole, fraction = (value.abs * (10**digits)).to_i.divmod(10**digits)
    "#{"-" if value.negative?}#{whole}.#{fraction.to_s.rjust(digits, "0")}r"
  end

  def add_mutation_with_replacement(node, replacement)
    add_mutation(offset: node.location.start_offset, length: node.location.length, replacement:, node:)
  end
end
