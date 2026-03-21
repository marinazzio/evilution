# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class NilReplacement < Base
        REPLACEMENTS = %w[true false 0 ""].freeze

        def visit_nil_node(node)
          REPLACEMENTS.each do |replacement|
            add_mutation(
              offset: node.location.start_offset,
              length: node.location.length,
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
