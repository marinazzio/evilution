# frozen_string_literal: true

class Evilution::Mutator::Operator::SymbolLiteral < Evilution::Mutator::Base
  def visit_symbol_node(node)
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
end
