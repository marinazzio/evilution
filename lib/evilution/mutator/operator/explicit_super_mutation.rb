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
  #
  # The argument list's byte range covers only the args themselves; the
  # separator (`,` + whitespace) between the last arg and a following
  # `&block` (or the closing `)` after a trailing comma) is owned by the
  # SuperNode itself. Replacing only `arguments.location` with `""` leaves
  # `super(, &block)` or `super(,)`. Extend the removal range to the start
  # of the block argument when present, otherwise to the closing paren — so
  # the separator goes along with the args.
  def emit_remove_all_args(node)
    start_offset = node.arguments.location.start_offset
    end_offset = trailing_args_boundary(node)

    add_mutation(
      offset: start_offset,
      length: end_offset - start_offset,
      replacement: "",
      node: node
    )
  end

  def trailing_args_boundary(node)
    return node.block.location.start_offset if node.block
    return node.rparen_loc.start_offset if node.rparen_loc

    node.arguments.location.end_offset
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
