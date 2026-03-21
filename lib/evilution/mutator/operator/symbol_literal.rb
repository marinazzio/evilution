# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class SymbolLiteral < Base
        def visit_symbol_node(node)
          add_mutation(
            offset: node.location.start_offset,
            length: node.location.length,
            replacement: ":__evilution_mutated__",
            node: node
          )

          add_mutation(
            offset: node.location.start_offset,
            length: node.location.length,
            replacement: "nil",
            node: node
          )

          super
        end
      end
    end
  end
end
