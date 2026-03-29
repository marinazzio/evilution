# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::NextStatement < Evilution::Mutator::Base
  def visit_next_node(node)
    generate_removal(node)
    generate_nil_value(node)
    generate_break_swap(node)

    super
  end

  private

  def generate_removal(node)
    loc = node.location

    add_mutation(
      offset: loc.start_offset,
      length: loc.length,
      replacement: "nil",
      node: node
    )
  end

  def generate_nil_value(node)
    return if node.arguments.nil?

    args_loc = node.arguments.location

    add_mutation(
      offset: args_loc.start_offset,
      length: args_loc.length,
      replacement: "nil",
      node: node
    )
  end

  def generate_break_swap(node)
    keyword_loc = node.keyword_loc

    add_mutation(
      offset: keyword_loc.start_offset,
      length: keyword_loc.length,
      replacement: "break",
      node: node
    )
  end
end
