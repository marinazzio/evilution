# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::NilReplacement < Evilution::Mutator::Base
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
