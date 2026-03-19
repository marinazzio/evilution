# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class RangeReplacement < Base
        def visit_range_node(node)
          replacement = node.operator == ".." ? "..." : ".."

          add_mutation(
            offset: node.operator_loc.start_offset,
            length: node.operator_loc.length,
            replacement: replacement,
            node: node
          )

          super
        end
      end
    end
  end
end
