# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::MethodBodyReplacement < Evilution::Mutator::Base
  REPLACEMENTS = %w[nil self super].freeze

  def visit_def_node(node)
    if node.body
      REPLACEMENTS.each do |replacement|
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
end
