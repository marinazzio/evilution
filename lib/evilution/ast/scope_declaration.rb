# frozen_string_literal: true

require "prism"
require_relative "../ast"

# An ActiveRecord scope declared with a literal body:
# `scope :recent, -> { where(recent: true) }`, or with `lambda { }` /
# `proc { }`. The body is what mutations go into; the name is the class
# method the declaration defines.
#
# Only the receiver-less form written directly in a class body counts: that
# is the call the mutated file re-runs to replace the scope, so the mutated
# body takes effect. A scope whose body is an object or a variable has no
# body of its own to mutate.
module Evilution::AST::ScopeDeclaration
  BLOCK_CALLS = %i[lambda proc].freeze
  private_constant :BLOCK_CALLS

  # The scope declarations among a class body's direct statements.
  def self.in_body(body)
    statements = body.is_a?(Prism::BeginNode) ? body.statements : body
    return [] unless statements

    statements.body.select { |node| body_of(node) }
  end

  # The node holding the scope's body -- a LambdaNode, or the BlockNode of a
  # `lambda` / `proc` call -- or nil when node is not a scope declaration.
  def self.body_of(node)
    return nil unless scope_call?(node)

    callable_body(node.arguments.arguments[1])
  end

  def self.scope_name(node)
    node.arguments.arguments.first.unescaped
  end

  def self.scope_call?(node)
    return false unless node.is_a?(Prism::CallNode) && node.name == :scope && node.receiver.nil?

    args = node.arguments ? node.arguments.arguments : []
    args.length == 2 && args.first.is_a?(Prism::SymbolNode)
  end

  def self.callable_body(node)
    return node if node.is_a?(Prism::LambdaNode)
    return nil unless node.is_a?(Prism::CallNode) && node.receiver.nil? && BLOCK_CALLS.include?(node.name)

    node.block if node.block.is_a?(Prism::BlockNode)
  end

  private_class_method :scope_call?, :callable_body
end
