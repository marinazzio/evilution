# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::InlineRescue < Evilution::Mutator::Base
  def visit_rescue_modifier_node(node)
    generate_rescue_removal(node)
    generate_nil_fallback(node)

    super
  end

  private

  def generate_rescue_removal(node)
    expr_end = node.expression.location.start_offset + node.expression.location.length
    rescue_end = node.rescue_expression.location.start_offset + node.rescue_expression.location.length

    add_mutation(
      offset: expr_end,
      length: rescue_end - expr_end,
      replacement: "",
      node: node
    )
  end

  def generate_nil_fallback(node)
    return if node.rescue_expression.is_a?(Prism::NilNode)

    fallback_loc = node.rescue_expression.location

    add_mutation(
      offset: fallback_loc.start_offset,
      length: fallback_loc.length,
      replacement: "nil",
      node: node
    )
  end
end
