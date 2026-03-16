# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class MethodCallRemoval < Base
        def visit_call_node(node)
          if node.receiver
            add_mutation(
              offset: node.location.start_offset,
              length: node.location.length,
              replacement: node.receiver.slice,
              node: node
            )
          end

          super
        end
      end
    end
  end
end
