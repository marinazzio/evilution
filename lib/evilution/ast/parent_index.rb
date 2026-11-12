# frozen_string_literal: true

require_relative "../ast"

# The parent of every node of a tree. Prism nodes do not point at their
# parent, so the tree is walked once and each node's parent recorded.
#
# A node is known by its type and the bytes it spans, not by identity: the
# nodes an operator mutates come from the subject's own parse of the file,
# which is not the tree the index was built from. Two nodes of different
# types can span the same bytes (a body of one statement and the statement),
# so the type is part of the key. Where a node of one type nests in another
# of the same type over the same bytes, the outer one's parent is kept, so
# the walk up never comes back to the key it left.
class Evilution::AST::ParentIndex
  def initialize(root)
    @parents = {}
    record(root)
  end

  # The node's ancestors, nearest first, up to the root of the tree. A node
  # the tree does not hold has none.
  def each_ancestor(node)
    parent = @parents[key(node)]
    while parent
      yield parent
      parent = @parents[key(parent)]
    end
  end

  private

  # Iterative: a deeply nested tree would overflow the stack of a recursive
  # walk.
  def record(root)
    pending = [root]
    until pending.empty?
      node = pending.pop
      node.compact_child_nodes.each do |child|
        @parents[key(child)] ||= node
        pending.push(child)
      end
    end
  end

  def key(node)
    location = node.location
    [node.class, location.start_offset, location.length]
  end
end
