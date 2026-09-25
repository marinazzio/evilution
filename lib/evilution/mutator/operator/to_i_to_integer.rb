# frozen_string_literal: true

require_relative "../operator"

# Replace a lenient `to_i` with the strict `Integer()` conversion:
# `value.to_i` becomes `Integer(value)`, `value.to_i(16)` becomes
# `Integer(value, 16)`.
#
# `to_i` never fails — malformed input ("abc", "12abc", "") and nil become 0
# or a leading-digits prefix — where `Integer()` raises. `Integer()` also
# honours radix prefixes ("0x1A" is 26, "012" is octal 10) that `to_i`
# ignores. A survivor means no test feeds invalid or prefixed input.
#
# Numeric literal receivers are skipped: both conversions agree on them.
class Evilution::Mutator::Operator::ToIToInteger < Evilution::Mutator::Base
  NUMERIC_LITERALS = [Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::ImaginaryNode].freeze
  private_constant :NUMERIC_LITERALS

  def visit_call_node(node)
    rewrite(node) if node.name == :to_i && convertible?(node)
    super
  end

  private

  def convertible?(node)
    receiver = node.receiver
    receiver && node.block.nil? && NUMERIC_LITERALS.none? { |type| receiver.is_a?(type) }
  end

  def rewrite(node)
    arguments = node.arguments ? node.arguments.arguments : []
    return if arguments.length > 1 || arguments.any?(Prism::SplatNode)

    parts = [node.receiver, *arguments].map { |part| source_of(part) }
    replace_span(node: node, target: node, replacement: "Integer(#{parts.join(", ")})")
  end
end
