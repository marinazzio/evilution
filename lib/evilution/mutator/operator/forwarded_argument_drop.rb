# frozen_string_literal: true

require_relative "../operator"

# Stop forwarding one part of the arguments a method passes through unnamed:
# `target.call(*, **, &)` becomes `target.call(**, &)`, and so on for each part.
#
# A survivor means that part never reaches an assertion — nothing checks that
# the positional arguments, the keywords or the block arrive at the other end.
#
# Two spellings are handled. Anonymous `*` and `**` are dropped from the
# argument list they are written in. A `...` cannot be split where it stands,
# because `*`, `**` and `&` may not be written under a `...` signature, so the
# signature is spelled out as `(*, **, &)` along with every use, and one use
# loses one part: `def f(...) = g(...)` becomes `def f(*, **, &) = g(**, &)`.
#
# Named splats are left to SplatOperator and KeywordArgument, and an anonymous
# `&` written on its own to BlockPassRemoval.
class Evilution::Mutator::Operator::ForwardedArgumentDrop < Evilution::Mutator::Base
  PARTS = ["*", "**", "&"].freeze
  ALL_PARTS = PARTS.join(", ").freeze

  def visit_def_node(node)
    drop_forwarded_parts(node)
    super
  end

  def visit_call_node(node)
    drop_anonymous_arguments(node)
    super
  end

  def visit_super_node(node)
    drop_anonymous_arguments(node)
    super
  end

  def visit_yield_node(node)
    drop_anonymous_arguments(node)
    super
  end

  private

  def drop_anonymous_arguments(node)
    return if node.arguments.nil?

    items = argument_items(node.arguments)
    # Dropping the only argument leaves an empty list, which is the mutant
    # ArgumentListRemoval already emits.
    return if items.length < 2

    items.each_index do |index|
      emit_argument_drop(node, items, index) if anonymous?(items[index])
    end
  end

  # Keywords sit together in one KeywordHashNode, `**` among them; they are
  # listed individually so each can be dropped on its own.
  def argument_items(arguments)
    arguments.arguments.flat_map do |argument|
      argument.is_a?(Prism::KeywordHashNode) ? argument.elements : [argument]
    end
  end

  def anonymous?(item)
    case item
    when Prism::SplatNode then item.expression.nil?
    when Prism::AssocSplatNode then item.value.nil?
    else false
    end
  end

  def emit_argument_drop(node, items, index)
    remaining = items.map(&:slice)
    remaining.delete_at(index)
    location = node.arguments.location

    add_mutation(
      offset: location.start_offset,
      length: location.length,
      replacement: remaining.join(", "),
      node: node
    )
  end

  def drop_forwarded_parts(node)
    return if node.body.nil?

    uses = forwarding_uses(node.body)
    uses.each do |target|
      PARTS.each { |part| emit_part_drop(node, uses, target, part) }
    end
  end

  # Every `...` the method forwards. A method defined in the body is not
  # searched: its `...` forwards that method's own arguments.
  def forwarding_uses(node)
    return [] if node.is_a?(Prism::DefNode)
    return [node] if node.is_a?(Prism::ForwardingArgumentsNode)

    node.compact_child_nodes.flat_map { |child| forwarding_uses(child) }
  end

  # A `...` can only be forwarded by the method that declares it, so a use
  # found in the body means the signature ends in the matching parameter.
  def emit_part_drop(node, uses, target, part)
    edits = uses.map do |use|
      [use.location, use.equal?(target) ? (PARTS - [part]).join(", ") : ALL_PARTS]
    end
    edits << [node.parameters.keyword_rest.location, ALL_PARTS]

    emit_rewrite(node, edits.sort_by { |location, _text| location.start_offset })
  end

  # The signature and the uses are apart in the source, while a mutation
  # replaces one contiguous range, so the range runs from the first edit to
  # the last and is rewritten with every edit applied.
  def emit_rewrite(node, edits)
    start_offset = edits.first.first.start_offset
    length = edits.last.first.end_offset - start_offset

    add_mutation(
      offset: start_offset,
      length: length,
      replacement: apply_edits(byteslice_source(start_offset, length), edits, start_offset),
      node: node
    )
  end

  # Applied last to first, so an edit never shifts the offsets of those still
  # to come.
  def apply_edits(text, edits, base_offset)
    edits.reverse_each do |location, replacement|
      text = text.byteslice(0, location.start_offset - base_offset) +
             replacement +
             text.byteslice((location.end_offset - base_offset)..)
    end

    text
  end
end
