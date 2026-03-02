# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class NegationInsertion < Base
        def visit_call_node(node)
          if node.name.to_s.end_with?("?")
            add_mutation(
              offset: node.location.start_offset,
              length: 0,
              replacement: "!",
              node: node
            )
          end

          super
        end
      end
    end
  end
end
