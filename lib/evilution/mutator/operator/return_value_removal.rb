# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class ReturnValueRemoval < Base
        def visit_return_node(node)
          if node.arguments
            add_mutation(
              offset: node.location.start_offset,
              length: node.location.length,
              replacement: "return",
              node: node
            )
          end

          super
        end
      end
    end
  end
end
