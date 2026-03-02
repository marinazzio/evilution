# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class ConditionalNegation < Base
        def visit_if_node(node)
          mutate_predicate(node)
          super
        end

        def visit_unless_node(node)
          mutate_predicate(node)
          super
        end

        private

        def mutate_predicate(node)
          add_mutation(
            offset: node.predicate.location.start_offset,
            length: node.predicate.location.length,
            replacement: "true",
            node: node
          )
          add_mutation(
            offset: node.predicate.location.start_offset,
            length: node.predicate.location.length,
            replacement: "false",
            node: node
          )
        end
      end
    end
  end
end
