# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class StringLiteral < Base
        def visit_string_node(node)
          replacement = node.content.empty? ? '"mutation"' : '""'

          add_mutation(
            offset: node.location.start_offset,
            length: node.location.length,
            replacement: replacement,
            node: node
          )

          super
        end
      end
    end
  end
end
