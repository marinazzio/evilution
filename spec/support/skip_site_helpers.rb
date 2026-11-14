# frozen_string_literal: true

require "prism"
require "evilution/ast/parent_index"

# Builds the chain a skip-site preset is asked about: the node an operator
# would mutate, then its ancestors, nearest first.
module SkipSiteHelpers
  # The node of the given type whose source is exactly `slice`; the nth one,
  # in source order, when the slice occurs more than once.
  def chain_at(source, slice, type, nth: 0)
    tree = Prism.parse(source).value
    node = nodes_in(tree).select { |candidate| candidate.is_a?(type) && candidate.slice == slice }.fetch(nth)
    [node, *Evilution::AST::ParentIndex.new(tree).enum_for(:each_ancestor, node).to_a]
  end

  def covered?(source, slice, type, nth: 0)
    described_class.new.covers?(chain_at(source, slice, type, nth: nth))
  end

  private

  def nodes_in(root)
    nodes = []
    pending = [root]
    until pending.empty?
      node = pending.pop
      nodes << node
      pending.concat(node.compact_child_nodes.reverse)
    end
    nodes
  end
end
