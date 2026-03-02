# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class MethodBodyReplacement < Base
        def visit_def_node(node)
          if node.body
            add_mutation(
              offset: node.body.location.start_offset,
              length: node.body.location.length,
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
