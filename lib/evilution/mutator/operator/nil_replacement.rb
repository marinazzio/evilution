# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class NilReplacement < Base
        def visit_nil_node(node)
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
