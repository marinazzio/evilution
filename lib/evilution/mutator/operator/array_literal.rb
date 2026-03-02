# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class ArrayLiteral < Base
        def visit_array_node(node)
          if node.opening_loc && node.elements.any?
            add_mutation(
              offset: node.location.start_offset,
              length: node.location.length,
              replacement: "[]",
              node: node
            )
          end

          super
        end
      end
    end
  end
end
