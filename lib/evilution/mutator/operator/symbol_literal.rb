# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::SymbolLiteral < Evilution::Mutator::Base
  def visit_symbol_node(node)
    return super if label_form?(node)

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

  private

  def label_form?(node)
    closing = node.closing_loc
    !closing.nil? && closing.slice == ":"
  end
end
