# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ArgumentNilSubstitution < Evilution::Mutator::Base
  SKIP_TYPES = [
    Prism::SplatNode,
    Prism::KeywordHashNode,
    Prism::BlockArgumentNode,
    Prism::ForwardingArgumentsNode
  ].freeze

  def visit_call_node(node)
    args = node.arguments&.arguments
    args.each_index { |i| emit_nil_substitution(node, args, i) } if mutable?(node, args)

    super
  end

  private

  def emit_nil_substitution(node, args, i)
    parts = args.each_with_index.map { |a, j| j == i ? "nil" : a.slice }
    add_mutation(
      offset: node.arguments.location.start_offset,
      length: node.arguments.location.length,
      replacement: parts.join(", "),
      node: node
    )
  end

  def mutable?(node, args)
    args && args.length >= 1 && positional_only?(args) && node.name != :[]=
  end

  def positional_only?(args)
    args.none? { |arg| SKIP_TYPES.any? { |type| arg.is_a?(type) } }
  end
end
