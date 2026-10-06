# frozen_string_literal: true

require_relative "../guarded_index_fetch"

# The nodes from the subject down to the `recv[key]` call a mutation rewrote,
# outermost first; nil when it cannot be found.
#
# Line and column are not enough: in `a[:x][:y]` the outer and the inner read
# start at the same place. The mutated source settles it -- the rewritten read
# is the one whose receiver is now followed by `.fetch(`.
class Evilution::Equivalent::Heuristic::GuardedIndexFetch::NodePath
  FETCH_CALL = ".fetch("

  def call(mutation)
    root = mutation.subject.node
    mutated_source = mutation.mutated_source
    return nil unless root && mutated_source

    search(root, mutation, mutated_source, [])
  end

  private

  def search(node, mutation, mutated_source, ancestors)
    path = ancestors + [node]
    return path if rewritten?(node, mutation, mutated_source)

    node.compact_child_nodes.each do |child|
      found = search(child, mutation, mutated_source, path)
      return found if found
    end
    nil
  end

  def rewritten?(node, mutation, mutated_source)
    return false unless node.is_a?(Prism::CallNode) && node.name == :[] && node.receiver

    location = node.location
    return false unless location.start_line == mutation.line && location.start_column == mutation.column

    mutated_source.byteslice(node.receiver.location.end_offset, FETCH_CALL.bytesize) == FETCH_CALL
  end
end
