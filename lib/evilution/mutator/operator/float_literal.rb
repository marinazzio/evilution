# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::FloatLiteral < Evilution::Mutator::Base
  # NaN fails every comparison and equality; the infinities break arithmetic
  # on bounds. None of them can be reached from `0.0`, `1.0` or `nil`.
  SPECIAL_VALUES = ["Float::NAN", "Float::INFINITY", "-Float::INFINITY"].freeze

  # A guard wraps the pattern of its branch: `in Float if x > 1.0`.
  GUARDS = [Prism::IfNode, Prism::UnlessNode].freeze

  def visit_float_node(node)
    add_mutation_with_replacement(node, node.value == 0.0 ? "1.0" : "0.0")
    SPECIAL_VALUES.each { |value| add_mutation_with_replacement(node, value) } unless pattern_literals.include?(node)
    add_mutation_with_replacement(node, "nil")

    super
  end

  # A pattern takes literals, not expressions: `in -Float::INFINITY` and
  # `in Float::NAN..2.0` do not parse. The floats of a pattern keep the
  # literal replacements only. A guard and a pinned expression (`^(x + 1.0)`)
  # are ordinary code.
  def visit_in_node(node)
    pattern = node.pattern
    pattern = pattern.statements if GUARDS.include?(pattern.class)
    mark_pattern_literals(pattern)
    super
  end

  def visit_match_predicate_node(node)
    mark_pattern_literals(node.pattern)
    super
  end

  def visit_match_required_node(node)
    mark_pattern_literals(node.pattern)
    super
  end

  # A complex literal (`5i`) is replaced as a whole by ComplexLiteral. Its
  # numeric part is not a literal of its own: `nili` is not a value.
  def visit_imaginary_node(_node); end

  private

  def pattern_literals
    @pattern_literals ||= Set.new.compare_by_identity
  end

  def mark_pattern_literals(node)
    return if node.is_a?(Prism::PinnedExpressionNode)

    pattern_literals.add(node) if node.is_a?(Prism::FloatNode)
    node.compact_child_nodes.each { |child| mark_pattern_literals(child) }
  end

  def add_mutation_with_replacement(node, replacement)
    add_mutation(offset: node.location.start_offset, length: node.location.length, replacement:, node:)
  end
end
