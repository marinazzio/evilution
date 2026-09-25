# frozen_string_literal: true

require_relative "../operator"

# Replace an `Array()` coercion with an array literal: `Array(value)` becomes
# `[value]`, and the same for `Kernel.Array(value)` / `Kernel::Array(value)`.
#
# The two agree only on a plain scalar. `Array(nil)` is `[]` where `[nil]`
# is not, an array or hash is converted rather than wrapped, and anything
# responding to `to_ary` / `to_a` is unpacked. A survivor means no test
# passes nil or a collection through the coercion.
class Evilution::Mutator::Operator::ArrayCoercionToLiteral < Evilution::Mutator::Base
  def visit_call_node(node)
    rewrite(node) if node.name == :Array && kernel_receiver?(node.receiver) && node.block.nil?
    super
  end

  private

  def rewrite(node)
    return unless node.arguments in Prism::ArgumentsNode[arguments: [argument]]
    return if argument.is_a?(Prism::SplatNode)

    replace_span(node: node, target: node, replacement: "[#{source_of(argument)}]")
  end

  def kernel_receiver?(receiver)
    case receiver
    when nil then true
    when Prism::ConstantReadNode then receiver.name == :Kernel
    when Prism::ConstantPathNode then receiver.parent.nil? && receiver.name == :Kernel
    end
  end
end
