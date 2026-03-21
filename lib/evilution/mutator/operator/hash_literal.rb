# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class HashLiteral < Base
        def visit_hash_node(node)
          if node.elements.any?
            add_mutation(
              offset: node.location.start_offset,
              length: node.location.length,
              replacement: "{}",
              node: node
            )

            add_mutation(
              offset: node.location.start_offset,
              length: node.location.length,
              replacement: "nil",
              node: node
            )
          end

          super
        end
      end
    end
  end
end
