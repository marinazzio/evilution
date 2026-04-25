# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::MethodBodyReplacement < Evilution::Mutator::Base
  ALWAYS_SAFE_REPLACEMENTS = %w[nil self].freeze
  SUPER_REPLACEMENT = "super"

  def visit_def_node(node)
    if node.body
      replacements = ALWAYS_SAFE_REPLACEMENTS.dup
      replacements << SUPER_REPLACEMENT if body_calls_super?(node.body)

      replacements.each do |replacement|
        add_mutation(
          offset: node.body.location.start_offset,
          length: node.body.location.length,
          replacement: replacement,
          node: node
        )
      end
    end

    super
  end

  private

  # The bare-super replacement raises NoMethodError at runtime when the enclosing
  # class has no parent implementation of the method. We emit it only when the
  # original body already calls super — proving the super target exists in this
  # context. See EV-ilu3.
  def body_calls_super?(node)
    return true if node.is_a?(Prism::SuperNode) || node.is_a?(Prism::ForwardingSuperNode)

    node.compact_child_nodes.any? { |child| body_calls_super?(child) }
  end
end
