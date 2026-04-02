# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::CollectionReturn < Evilution::Mutator::Base
  def visit_def_node(node)
    body = node.body
    if body.is_a?(Prism::StatementsNode) && body.body.length > 1
      return_node = body.body.last
      replacement = collection_replacement(return_node)

      if replacement
        add_mutation(
          offset: body.location.start_offset,
          length: body.location.length,
          replacement: replacement,
          node: node
        )
      end
    end

    super
  end

  def collection_replacement(node)
    case node
    when Prism::ArrayNode
      "[]" if node.elements.any?
    when Prism::HashNode
      "{}" if node.elements.any?
    end
  end
end
