# frozen_string_literal: true

class Evilution::Mutator::Operator::StatementDeletion < Evilution::Mutator::Base
  def visit_statements_node(node)
    if node.body.length > 1
      node.body.each do |child|
        add_mutation(
          offset: child.location.start_offset,
          length: child.location.length,
          replacement: "",
          node: child
        )
      end
    end

    super
  end
end
