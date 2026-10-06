# frozen_string_literal: true

require "prism"
require_relative "../ast"

# A callable written out where it is used: `-> { }`, `lambda { }` or
# `proc { }`. Its body is what mutations go into. A constant, a variable or
# `method(:name)` in the same place has no body of its own to mutate.
module Evilution::AST::LiteralCallable
  BLOCK_CALLS = %i[lambda proc].freeze
  private_constant :BLOCK_CALLS

  # The node holding the callable's body -- a LambdaNode, or the BlockNode of
  # a `lambda` / `proc` call -- or nil when node is not a literal callable.
  def self.body_of(node)
    return node if node.is_a?(Prism::LambdaNode)
    return nil unless node.is_a?(Prism::CallNode) && node.receiver.nil? && BLOCK_CALLS.include?(node.name)

    node.block if node.block.is_a?(Prism::BlockNode)
  end
end
