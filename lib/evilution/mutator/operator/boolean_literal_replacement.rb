# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class BooleanLiteralReplacement < Base
        def visit_true_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: node.location.length,
            replacement: "false",
            node: node
          )

          super
        end

        def visit_false_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: node.location.length,
            replacement: "true",
            node: node
          )

          super
        end
      end
    end
  end
end
