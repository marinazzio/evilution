# frozen_string_literal: true

require_relative "../operator"

# Swap the numbered parameters of a block: `pairs.map { _1 - _2 }` becomes
# `pairs.map { _2 - _1 }`.
#
# A survivor means no example tells the two values apart, so the block could
# take them in either order unnoticed.
#
# Only parameters the body reads are swapped with each other, each with its
# neighbour. Swapping in a parameter the body never reads (`{ _1 }` to
# `{ _2 }`) would change how many values the block takes, which is a different
# mutation from reordering them.
class Evilution::Mutator::Operator::NumberedParameterSwap < Evilution::Mutator::Base
  NUMBERED_NAME = /\A_[1-9]\z/

  def visit_block_node(node)
    swap_parameters(node)
    super
  end

  def visit_lambda_node(node)
    swap_parameters(node)
    super
  end

  private

  def swap_parameters(node)
    return unless node.parameters.is_a?(Prism::NumberedParametersNode)

    reads = numbered_reads(node.body)
    names = reads.map { |read| read.name.to_s }.uniq.sort
    names.each_cons(2) { |left, right| emit_swap(node, reads, left, right) }
  end

  # Every read of a numbered parameter in the body. Blocks nested in it are
  # searched too: a numbered parameter read there can only be this block's,
  # since Ruby rejects a nested block that declares its own. A method defined
  # in the body opens a new scope, whose blocks have parameters of their own.
  def numbered_reads(node)
    return [] if node.is_a?(Prism::DefNode)
    return [node] if node.is_a?(Prism::LocalVariableReadNode) && node.name.to_s.match?(NUMBERED_NAME)

    node.compact_child_nodes.flat_map { |child| numbered_reads(child) }
  end

  # The reads are scattered through the body, while a mutation replaces one
  # contiguous range, so the range runs from the first affected read to the
  # last and is rewritten with the two names exchanged.
  def emit_swap(node, reads, left, right)
    affected = reads.select { |read| [left, right].include?(read.name.to_s) }
                    .sort_by { |read| read.location.start_offset }
    start_offset = affected.first.location.start_offset
    end_offset = affected.last.location.end_offset

    add_mutation(
      offset: start_offset,
      length: end_offset - start_offset,
      replacement: exchange(affected, start_offset, end_offset, left => right, right => left),
      node: node
    )
  end

  def exchange(affected, start_offset, end_offset, renames)
    text = byteslice_source(start_offset, end_offset - start_offset)

    affected.reverse_each do |read|
      location = read.location
      text = text.byteslice(0, location.start_offset - start_offset) +
             renames.fetch(read.name.to_s) +
             text.byteslice((location.end_offset - start_offset)..)
    end

    text
  end
end
