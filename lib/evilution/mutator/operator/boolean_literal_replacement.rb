# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::BooleanLiteralReplacement < Evilution::Mutator::Base
  def visit_true_node(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "false",
      node: node
    )

    add_nil_mutation(node)

    super
  end

  def visit_false_node(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "true",
      node: node
    )

    add_nil_mutation(node)

    super
  end

  private

  def add_nil_mutation(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "nil",
      node: node
    )
  end
end
