# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::IntegerLiteral < Evilution::Mutator::Base
  def visit_integer_node(node)
    if node.value.zero?
      add_mutation_with_replacement(node, "1")
    elsif node.value == 1
      add_mutation_with_replacement(node, "0")
    else
      add_mutation_with_replacement(node, "0")
      add_mutation_with_replacement(node, (node.value + 1).to_s)
    end

    add_mutation_with_replacement(node, "nil")

    super
  end

  private

  def add_mutation_with_replacement(node, replacement)
    add_mutation(offset: node.location.start_offset, length: node.location.length, replacement:, node:)
  end
end
