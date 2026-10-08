# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::IntegerLiteral < Evilution::Mutator::Base
  # One value past each integer width, keyed by the boundary it crosses:
  # int8, uint8, int16, uint16, int32, uint32, int64. A literal is replaced
  # with the sentinel of the first boundary above its magnitude, so a
  # survivor means nothing checks that the value still fits its width. The
  # sentinels are safe primes: arithmetic, masking or shifting does not land
  # on one by coincidence.
  WIDTH_SENTINELS = {
    2**7 => 167,
    2**8 => 467,
    2**15 => 55_487,
    2**16 => 108_503,
    2**31 => 2_667_278_543,
    2**32 => 7_980_081_959,
    2**63 => 15_508_464_536_481_899_903
  }.freeze

  def visit_integer_node(node)
    replacements_for(node.value).each { |value| add_mutation_with_replacement(node, value.to_s) }
    add_mutation_with_replacement(node, "nil")

    super
  end

  # A complex literal (`5i`) is replaced as a whole by ComplexLiteral. Its
  # numeric part is not a literal of its own: `nili` is not a value.
  def visit_imaginary_node(_node); end

  private

  def replacements_for(value)
    [*neighbours_of(value), width_sentinel_for(value)].compact
  end

  def neighbours_of(value)
    return [1, -1] if value.zero?
    return [0] if value == 1

    [0, value + 1, value - 1].uniq
  end

  def width_sentinel_for(value)
    _boundary, sentinel = WIDTH_SENTINELS.find { |boundary, _| boundary > value.abs }
    sentinel
  end

  def add_mutation_with_replacement(node, replacement)
    add_mutation(offset: node.location.start_offset, length: node.location.length, replacement:, node:)
  end
end
