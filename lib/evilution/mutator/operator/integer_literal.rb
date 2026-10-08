# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::IntegerLiteral < Evilution::Mutator::Base
  def visit_integer_node(node)
    replacements_for(node.value).each { |value| add_mutation_with_replacement(node, value.to_s) }
    add_mutation_with_replacement(node, "nil")

    super
  end

  private

  def replacements_for(value)
    return [1, -1] if value.zero?
    return [0] if value == 1

    [0, value + 1, value - 1].uniq
  end

  def add_mutation_with_replacement(node, replacement)
    add_mutation(offset: node.location.start_offset, length: node.location.length, replacement:, node:)
  end
end
