# frozen_string_literal: true

require "prism"

require_relative "../operator"

# Flatten a destructuring group in a block's parameter list:
# `pairs.each_with_index { |(key, value), index| ... }` becomes
# `pairs.each_with_index { |key, value, index| ... }`.
#
# The two forms bind differently once the group has a sibling: given `[1, 2]`
# and `3`, the grouped form binds key=1, value=2, index=3, while the flat form
# binds key=[1, 2], value=3, index=nil. A survivor means nothing asserts the
# shape of what the yielder hands over.
#
# A lone group is left alone. With one parameter and a single yielded array —
# what `each` over pairs, and `Hash#each`, actually yield — both forms bind the
# same values, so the mutation would be behaviour-preserving and survive every
# suite. The forms do diverge there for a yielder that passes several values,
# but which one a block is handed cannot be known from the source, and a
# guaranteed survivor on the common idiom is the worse trade.
#
# Methods and lambdas are left alone as well: both bind by arity, so flattening
# a group in their signatures raises ArgumentError at every call site instead of
# changing how arguments are distributed.
class Evilution::Mutator::Operator::BlockDestructuringExpansion < Evilution::Mutator::Base
  def visit_block_node(node)
    expand_groups(node)
    super
  end

  private

  def expand_groups(node)
    parameters = node.parameters
    return unless parameters.is_a?(Prism::BlockParametersNode)

    inner = parameters.parameters
    return unless inner.is_a?(Prism::ParametersNode)
    return unless siblings?(inner)

    groups(inner).each { |group| flatten_group(group) }
  end

  # Both lists can hold a destructuring group: `|(a, b), c|` puts it in
  # requireds, `|*rest, (a, b)|` in posts.
  def groups(parameters)
    [*parameters.requireds, *parameters.posts].grep(Prism::MultiTargetNode)
  end

  def siblings?(parameters)
    parameter_count(parameters) > 1
  end

  # Block-local variables (`|a; tmp|`) are not parameters and so are not
  # siblings — they change nothing about how arguments bind.
  def parameter_count(parameters)
    [
      *parameters.requireds,
      *parameters.optionals,
      parameters.rest,
      *parameters.posts,
      *parameters.keywords,
      parameters.keyword_rest,
      parameters.block
    ].compact.length
  end

  # Only the group's own parentheses go; anything nested inside keeps its own.
  # A group written in a block's parameter list always carries them — the
  # parenthesis-free MultiTargetNode belongs to multiple assignment, which is
  # not reachable from here.
  def flatten_group(group)
    lparen = group.lparen_loc
    rparen = group.rparen_loc

    inner_start = lparen.start_offset + lparen.length
    add_mutation(
      offset: group.location.start_offset,
      length: group.location.length,
      replacement: byteslice_source(inner_start, rparen.start_offset - inner_start),
      node: group
    )
  end
end
