# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::BooleanOperatorReplacement < Evilution::Mutator::Base
  REPLACEMENTS = {
    "&&" => "||",
    "||" => "&&",
    "and" => "or",
    "or" => "and"
  }.freeze

  def visit_and_node(node)
    loc = node.operator_loc
    operator = loc.slice
    replacement = REPLACEMENTS[operator]

    if replacement
      add_mutation(
        offset: loc.start_offset,
        length: loc.length,
        replacement: replacement,
        node: node
      )
    end

    super
  end

  def visit_or_node(node)
    loc = node.operator_loc
    operator = loc.slice
    replacement = REPLACEMENTS[operator]

    if replacement
      add_mutation(
        offset: loc.start_offset,
        length: loc.length,
        replacement: replacement,
        node: node
      )
    end

    super
  end
end
