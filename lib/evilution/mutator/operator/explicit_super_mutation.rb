# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ExplicitSuperMutation < Evilution::Mutator::Base
  def visit_super_node(node)
    replace_with_zsuper(node)
    args = node.arguments&.arguments
    mutate_arguments(node, args) if args && !args.empty?

    super
  end

  private

  def replace_with_zsuper(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "super",
      node: node
    )
  end

  def mutate_arguments(node, args)
    emit_remove_all_args(node)
    return unless args.length >= 2

    args.each_index { |i| emit_remove_arg_at(node, args, i) }
  end

  # super(a, b) -> super()
  def emit_remove_all_args(node)
    add_mutation(
      offset: node.arguments.location.start_offset,
      length: node.arguments.location.length,
      replacement: "",
      node: node
    )
  end

  def emit_remove_arg_at(node, args, i)
    remaining = args.each_with_index.filter_map { |a, j| a.slice if j != i }
    add_mutation(
      offset: node.arguments.location.start_offset,
      length: node.arguments.location.length,
      replacement: remaining.join(", "),
      node: node
    )
  end
end
