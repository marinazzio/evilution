# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class RegexpMutation < Base
        NEVER_MATCH = 'a\A'
        ALWAYS_MATCH = ".*"

        REPLACEMENTS = [NEVER_MATCH, ALWAYS_MATCH].freeze

        def visit_regular_expression_node(node)
          REPLACEMENTS.each do |replacement|
            add_mutation(
              offset: node.content_loc.start_offset,
              length: node.content_loc.length,
              replacement: replacement,
              node: node
            )
          end

          super
        end
      end
    end
  end
end
