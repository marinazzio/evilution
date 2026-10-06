# frozen_string_literal: true

require_relative "../guarded_index_fetch"

# One `recv[key]` read, reduced to what makes another read "the same": the
# receiver's source and a literal key.
#
# The receiver has to be something that can be named twice and mean the same
# thing both times: a variable, a constant, or calls without arguments or
# block on one of those. `lookup(id)[:k]` is not.
class Evilution::Equivalent::Heuristic::GuardedIndexFetch::IndexRead
  KEY_TYPES = [Prism::SymbolNode, Prism::StringNode, Prism::IntegerNode].freeze
  NAMED_TYPES = [
    Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode,
    Prism::GlobalVariableReadNode, Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::SelfNode
  ].freeze

  attr_reader :receiver_source, :key_source, :root

  def self.from(node)
    key = single_argument(node)
    return nil unless key && literal?(key) && node.receiver && stable?(node.receiver)

    new(receiver_source: node.receiver.slice, key_source: key.slice, root: root_of(node.receiver))
  end

  def self.single_argument(node)
    return nil unless node.arguments && node.arguments.arguments.length == 1

    node.arguments.arguments.first
  end

  def self.literal?(node)
    KEY_TYPES.any? { |type| node.is_a?(type) }
  end

  def self.stable?(node)
    return true if NAMED_TYPES.any? { |type| node.is_a?(type) }
    return false unless node.is_a?(Prism::CallNode) && node.arguments.nil? && node.block.nil?

    node.receiver.nil? || stable?(node.receiver)
  end

  # The variable a receiver hangs off: `user` in `user.settings`.
  def self.root_of(node)
    node = node.receiver while node.is_a?(Prism::CallNode) && node.receiver
    node
  end

  def initialize(receiver_source:, key_source:, root:)
    @receiver_source = receiver_source
    @key_source = key_source
    @root = root
  end

  def root_name
    root.respond_to?(:name) ? root.name : nil
  end

  def local_root?
    root.is_a?(Prism::LocalVariableReadNode)
  end

  def instance_variable_root?
    root.is_a?(Prism::InstanceVariableReadNode)
  end

  # Whether a node is this read again: `recv[key]`.
  def same?(node)
    node.is_a?(Prism::CallNode) && node.name == :[] && on_receiver?(node) && keyed?(node)
  end

  def on_receiver?(call)
    !call.receiver.nil? && call.receiver.slice == receiver_source
  end

  # Whether a call's only argument is this read's key.
  def keyed?(call)
    key = self.class.single_argument(call)
    !key.nil? && key.slice == key_source
  end
end
