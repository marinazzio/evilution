# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class ArgumentNilSubstitution < Base
        SKIP_TYPES = [
          Prism::SplatNode,
          Prism::KeywordHashNode,
          Prism::BlockArgumentNode,
          Prism::ForwardingArgumentsNode
        ].freeze

        def visit_call_node(node)
          args = node.arguments&.arguments

          if args && args.length >= 1 && positional_only?(args)
            args.each_index do |i|
              parts = args.each_with_index.map { |a, j| j == i ? "nil" : a.slice }
              replacement = parts.join(", ")

              add_mutation(
                offset: node.arguments.location.start_offset,
                length: node.arguments.location.length,
                replacement: replacement,
                node: node
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
    end
  end
end
