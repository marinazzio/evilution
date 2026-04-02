# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::CollectionReturn < Evilution::Mutator::Base
  def visit_def_node(node)
    if node.body
      return_node = last_expression(node.body)
      replacement = collection_replacement(return_node)

      if replacement
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

  def last_expression(body)
    if body.is_a?(Prism::StatementsNode)
      body.body.last
    else
      body
    end
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
