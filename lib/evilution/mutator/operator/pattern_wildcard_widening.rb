# frozen_string_literal: true

require_relative "../operator"

# Widen a pattern so it accepts input the original rejects:
#
#   in [a, b]               ->  in [a, b, *]        longer arrays
#   in { age: Integer }     ->  in { age: _ }       any value under the key
#   in { name: String, age: Integer }
#                           ->  in { name: String } hashes without the key
#   in { kind: :a, **nil }  ->  in { kind: :a }     hashes with other keys
#
# A survivor means no example feeds the pattern one of the shapes it is written
# to turn away.
#
# Elements of array and find patterns are widened by PatternMatchingArray. Here
# the pattern itself is opened up, and every edit keeps the variables the
# pattern binds, so the branch body still runs as written.
class Evilution::Mutator::Operator::PatternWildcardWidening < Evilution::Mutator::Base
  WILDCARD = "_"
  UNWIDENABLE_VALUE_TYPES = [Prism::LocalVariableTargetNode, Prism::ImplicitNode].freeze

  def visit_array_pattern_node(node)
    append_rest(node)
    super
  end

  def visit_hash_pattern_node(node)
    widen_pairs(node)
    drop_closing_rest(node)
    super
  end

  private

  # A pattern with a rest is open already, at whichever end the rest sits, and
  # an empty one has no element to append after.
  def append_rest(node)
    return unless node.rest.nil?
    return if node.requireds.empty?

    add_mutation(
      offset: node.requireds.last.location.end_offset,
      length: 0,
      replacement: ", *",
      node: node
    )
  end

  def widen_pairs(node)
    node.elements.each_with_index do |pair, index|
      next if binds_variable?(pair.value)

      wildcard_value(node, pair)
      # `in {}` matches the empty hash only, so dropping the last key would
      # narrow the pattern rather than widen it.
      drop_pair(node, index) if node.elements.length > 1
    end
  end

  # A bare name reaching here is an underscore one, which already accepts any
  # value; rewriting it to `_` would change nothing. A shorthand key
  # (`_ignored:`) has no value pattern of its own: its implicit value spans the
  # key, so writing a wildcard there would rename the key instead.
  def wildcard_value(node, pair)
    return if UNWIDENABLE_VALUE_TYPES.include?(pair.value.class)

    location = pair.value.location

    add_mutation(
      offset: location.start_offset,
      length: location.length,
      replacement: WILDCARD,
      node: node
    )
  end

  def drop_pair(node, index)
    remaining = node.elements.dup
    remaining.delete_at(index)
    replace_members(node, remaining + [node.rest].compact)
  end

  # `**nil` forbids keys the pattern does not name. On its own it leaves a
  # pattern that matches the empty hash only, with or without it.
  def drop_closing_rest(node)
    return unless node.rest.is_a?(Prism::NoKeywordsParameterNode)
    return if node.elements.empty?

    replace_members(node, node.elements)
  end

  # Rewrites what sits between the delimiters, so braces, parentheses and a
  # constant in front of them stay as written.
  def replace_members(node, members)
    all = node.elements + [node.rest].compact
    start_offset = all.first.location.start_offset
    end_offset = all.last.location.end_offset

    add_mutation(
      offset: start_offset,
      length: end_offset - start_offset,
      replacement: members.map(&:slice).join(", "),
      node: node
    )
  end

  # Whether the value pattern captures into a variable the branch body could
  # read. Taking such a pair away, or widening it to a wildcard, would break
  # the body on the missing name whatever the tests assert. An underscore name
  # is a wildcard by convention and is not counted.
  def binds_variable?(node)
    return !node.name.start_with?(WILDCARD) if node.is_a?(Prism::LocalVariableTargetNode)

    node.compact_child_nodes.any? { |child| binds_variable?(child) }
  end
end
