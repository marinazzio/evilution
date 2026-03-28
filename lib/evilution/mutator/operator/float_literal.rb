# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::FloatLiteral < Evilution::Mutator::Base
  def visit_float_node(node)
    replacement = case node.value
                  when 0.0 then "1.0"
                  when 1.0 then "0.0"
                  else "0.0"
                  end

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: replacement,
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
