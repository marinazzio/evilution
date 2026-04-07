# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::LambdaBody < Evilution::Mutator::Base
  def visit_lambda_node(node)
    if node.body
      add_mutation(
        offset: node.body.location.start_offset,
        length: node.body.location.length,
        replacement: "nil",
        node: node
      )
    end

    super
  end
end
