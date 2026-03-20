# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class SendMutation < Base
        REPLACEMENTS = {
          flat_map: [:map],
          map: [:flat_map],
          collect: [:map],
          public_send: [:send],
          send: [:public_send],
          gsub: [:sub],
          sub: [:gsub],
          detect: [:find],
          find: [:detect],
          each_with_object: [:inject],
          inject: [:each_with_object],
          reverse_each: [:each],
          each: [:reverse_each],
          length: [:size],
          size: [:length],
          values_at: [:fetch_values],
          fetch_values: [:values_at]
        }.freeze

        def visit_call_node(node)
          replacements = REPLACEMENTS[node.name]
          return super unless replacements
          return super unless node.receiver

          loc = node.message_loc
          return super unless loc

          replacements.each do |replacement|
            add_mutation(
              offset: loc.start_offset,
              length: loc.length,
              replacement: replacement.to_s,
              node: node
            )
          end

          super
        end
      end
    end
  end
end
