# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ArgumentRemoval < Evilution::Mutator::Base
  SKIP_TYPES = [
    Prism::SplatNode,
    Prism::KeywordHashNode,
    Prism::BlockArgumentNode,
    Prism::ForwardingArgumentsNode
  ].freeze

  def visit_call_node(node)
    args = node.arguments&.arguments
    args.each_index { |i| emit_argument_removal(node, args, i) } if mutable?(node, args)

    super
  end

  private

  def emit_argument_removal(node, args, i)
    remaining = args.each_with_index.filter_map { |a, j| a.slice if j != i }
    add_mutation(
      offset: node.arguments.location.start_offset,
      length: node.arguments.location.length,
      replacement: remaining.join(", "),
      node: node
    )
  end

  def mutable?(node, args)
    args && args.length >= 2 && positional_only?(args) && node.name != :[]=
  end

  def positional_only?(args)
    args.none? { |arg| SKIP_TYPES.any? { |type| arg.is_a?(type) } }
  end
end
