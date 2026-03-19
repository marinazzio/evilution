# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class ConditionalFlip < Base
        def visit_if_node(node)
          if node.if_keyword == "if" && !elsif?(node)
            add_mutation(
              offset: node.if_keyword_loc.start_offset,
              length: node.if_keyword_loc.length,
              replacement: "unless",
              node: node
            )
          end

          super
        end

        def visit_unless_node(node)
          add_mutation(
            offset: node.keyword_loc.start_offset,
            length: node.keyword_loc.length,
            replacement: "if",
            node: node
          )

          super
        end

        private

        def elsif?(node)
          node.subsequent.is_a?(Prism::IfNode)
        end
      end
    end
  end
end
