# frozen_string_literal: true

require_relative "../operator"

# Replace a complex literal (`5i`) with `0i`, `1i`, its two neighbours along
# the imaginary axis (`6i`, `4i`) and `nil`.
#
# The literal is replaced as a whole: IntegerLiteral and FloatLiteral leave
# its numeric part alone.
class Evilution::Mutator::Operator::ComplexLiteral < Evilution::Mutator::Base
  def visit_imaginary_node(node)
    replacements_for(node.numeric).each { |part| add_mutation_with_replacement(node, "#{part}i") }
    add_mutation_with_replacement(node, "nil")

    super
  end

  private

  # Equal values are emitted once, the integer first: `1i` over `1.0i`.
  def replacements_for(numeric)
    part = numeric.value
    [0, 1, *neighbours_of(numeric)].reject { |candidate| candidate == part }.uniq(&:to_r)
  end

  # A rational part (`3ri`) gets none: its neighbours have no literal of
  # their own in general.
  def neighbours_of(numeric)
    return [] if numeric.is_a?(Prism::RationalNode)

    [numeric.value + 1, numeric.value - 1]
  end

  def add_mutation_with_replacement(node, replacement)
    add_mutation(offset: node.location.start_offset, length: node.location.length, replacement:, node:)
  end
end
