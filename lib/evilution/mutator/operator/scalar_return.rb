# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ScalarReturn < Evilution::Mutator::Base
  def visit_def_node(node)
    body = node.body
    if body.is_a?(Prism::StatementsNode) && body.body.length > 1
      return_node = body.body.last
      replacement = scalar_replacement(return_node)

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

  private

  def scalar_replacement(node)
    case node
    when Prism::StringNode
      '""' unless node.content.empty?
    when Prism::IntegerNode
      "0" unless node.value.zero?
    when Prism::FloatNode
      "0.0" unless node.value.zero?
    end
  end
end
