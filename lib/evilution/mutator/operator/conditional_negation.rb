# frozen_string_literal: true

class Evilution::Mutator::Operator::ConditionalNegation < Evilution::Mutator::Base
  def visit_if_node(node)
    mutate_predicate(node)
    super
  end

  def visit_unless_node(node)
    mutate_predicate(node)
    super
  end

  private

  def mutate_predicate(node)
    add_mutation(
      offset: node.predicate.location.start_offset,
      length: node.predicate.location.length,
      replacement: "true",
      node: node
    )
    add_mutation(
      offset: node.predicate.location.start_offset,
      length: node.predicate.location.length,
      replacement: "false",
      node: node
    )
  end
end
