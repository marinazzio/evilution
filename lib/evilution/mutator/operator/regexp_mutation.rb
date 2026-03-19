# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class RegexpMutation < Base
        NEVER_MATCH = 'a\A'

        def visit_regular_expression_node(node)
          add_mutation(
            offset: node.content_loc.start_offset,
            length: node.content_loc.length,
            replacement: NEVER_MATCH,
            node: node
          )

          super
        end
      end
    end
  end
end
