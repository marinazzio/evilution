# frozen_string_literal: true

require_relative "../guarded_index_fetch"

# Whether a guarded branch does anything that could take the key away again
# after the guard saw it: assigns the variable the receiver hangs off, or
# calls something on the receiver that changes it.
#
# The whole branch is searched, not just what precedes the read; inside a loop
# "before" and "after" trade places.
class Evilution::Equivalent::Heuristic::GuardedIndexFetch::Disturbance
  LOCAL_WRITES = [
    Prism::LocalVariableWriteNode, Prism::LocalVariableOperatorWriteNode, Prism::LocalVariableOrWriteNode,
    Prism::LocalVariableAndWriteNode, Prism::LocalVariableTargetNode
  ].freeze
  INSTANCE_VARIABLE_WRITES = [
    Prism::InstanceVariableWriteNode, Prism::InstanceVariableOperatorWriteNode,
    Prism::InstanceVariableOrWriteNode, Prism::InstanceVariableAndWriteNode, Prism::InstanceVariableTargetNode
  ].freeze
  MUTATORS = %i[[]= delete clear replace store update shift pop delete_if keep_if].freeze

  def initialize(read)
    @read = read
  end

  def in?(node)
    disturbs?(node) || node.compact_child_nodes.any? { |child| in?(child) }
  end

  private

  def disturbs?(node)
    reassigns_root?(node) || mutates_receiver?(node)
  end

  def reassigns_root?(node)
    writes = if @read.local_root?
               LOCAL_WRITES
             elsif @read.instance_variable_root?
               INSTANCE_VARIABLE_WRITES
             else
               []
             end
    writes.any? { |type| node.is_a?(type) } && node.name == @read.root_name
  end

  def mutates_receiver?(node)
    node.is_a?(Prism::CallNode) && @read.on_receiver?(node) && mutator?(node.name)
  end

  def mutator?(name)
    MUTATORS.include?(name) || name.end_with?("!")
  end
end
