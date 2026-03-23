# frozen_string_literal: true

module Evilution
  module Mutator
    module Operator
      class CompoundAssignment < Base
        REPLACEMENTS = {
          :+ => %i[- *],
          :- => [:+],
          :* => [:/],
          :/ => [:*],
          :% => [:*],
          :** => [:*],
          :& => %i[| ^],
          :| => [:&],
          :^ => [:&],
          :<< => [:>>],
          :>> => [:<<]
        }.freeze

        def visit_local_variable_operator_write_node(node)
          mutate_operator_write(node)
          super
        end

        def visit_instance_variable_operator_write_node(node)
          mutate_operator_write(node)
          super
        end

        def visit_class_variable_operator_write_node(node)
          mutate_operator_write(node)
          super
        end

        def visit_global_variable_operator_write_node(node)
          mutate_operator_write(node)
          super
        end

        def visit_local_variable_and_write_node(node)
          mutate_logical_write(node, "||=")
          super
        end

        def visit_local_variable_or_write_node(node)
          mutate_logical_write(node, "&&=")
          super
        end

        def visit_instance_variable_and_write_node(node)
          mutate_logical_write(node, "||=")
          super
        end

        def visit_instance_variable_or_write_node(node)
          mutate_logical_write(node, "&&=")
          super
        end

        def visit_class_variable_and_write_node(node)
          mutate_logical_write(node, "||=")
          super
        end

        def visit_class_variable_or_write_node(node)
          mutate_logical_write(node, "&&=")
          super
        end

        def visit_global_variable_and_write_node(node)
          mutate_logical_write(node, "||=")
          super
        end

        def visit_global_variable_or_write_node(node)
          mutate_logical_write(node, "&&=")
          super
        end

        private

        def mutate_logical_write(node, replacement)
          loc = node.operator_loc
          add_mutation(
            offset: loc.start_offset,
            length: loc.length,
            replacement: replacement,
            node: node
          )
        end

        def mutate_operator_write(node)
          replacements = REPLACEMENTS[node.binary_operator]
          return unless replacements

          loc = node.binary_operator_loc

          replacements.each do |replacement|
            replacement_str = "#{replacement}="
            add_mutation(
              offset: loc.start_offset,
              length: loc.length,
              replacement: replacement_str,
              node: node
            )
          end
        end
      end
    end
  end
end
