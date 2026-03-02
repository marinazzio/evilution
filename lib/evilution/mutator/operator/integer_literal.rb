# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class IntegerLiteral < Base
        def visit_integer_node(node)
          value = node.value

          if value.zero?
            add_mutation(
              offset: node.location.start_offset,
              length: node.location.length,
              replacement: "1",
              node: node
            )
          elsif value == 1
            add_mutation(
              offset: node.location.start_offset,
              length: node.location.length,
              replacement: "0",
              node: node
            )
          else
            add_mutation(
              offset: node.location.start_offset,
              length: node.location.length,
              replacement: "0",
              node: node
            )

            add_mutation(
              offset: node.location.start_offset,
              length: node.location.length,
              replacement: (node.value + 1).to_s,
              node: node
            )
          end

          super
        end
      end
    end
  end
end
