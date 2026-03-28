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

    if args && args.length >= 2 && positional_only?(args)
      args.each_index do |i|
        remaining = args.each_with_index.filter_map { |a, j| a.slice if j != i }
        replacement = remaining.join(", ")

        add_mutation(
          offset: node.arguments.location.start_offset,
          length: node.arguments.location.length,
          replacement:,
          node:
        )
      end
    end

    super
  end

  private

  def positional_only?(args)
    args.none? { |arg| SKIP_TYPES.any? { |type| arg.is_a?(type) } }
  end
end
