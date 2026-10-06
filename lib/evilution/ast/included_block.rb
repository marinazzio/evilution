# frozen_string_literal: true

require "prism"
require_relative "../ast"

# The block of an `ActiveSupport::Concern`'s `included do ... end`: code
# written in a module body that runs in the body of each class including the
# module. Only the receiver-less, argument-less form with a literal block
# counts -- `def self.included(base)` and `included(base) { }` are plain Ruby
# hooks with rules of their own.
module Evilution::AST::IncludedBlock
  # The block node, or nil when node is not an `included` block call.
  def self.of(node)
    return nil unless node.is_a?(Prism::CallNode) && node.name == :included
    return nil unless node.receiver.nil? && node.arguments.nil?

    node.block if node.block.is_a?(Prism::BlockNode)
  end

  # The included blocks among a module body's direct statements.
  def self.in_body(body)
    statements = body.is_a?(Prism::BeginNode) ? body.statements : body
    return [] unless statements.is_a?(Prism::StatementsNode)

    statements.body.filter_map { |node| of(node) }
  end
end
