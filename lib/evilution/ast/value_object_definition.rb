# frozen_string_literal: true

require "prism"
require_relative "../ast"

# A value-object definition: `Data.define(...)` or `Struct.new(...)` called on
# the core class itself (`Data` or `::Data`, not `Foo::Data`), with or without
# a block.
module Evilution::AST::ValueObjectDefinition
  DEFINERS = { Data: :define, Struct: :new }.freeze

  def self.match?(node)
    return false unless node.is_a?(Prism::CallNode) && core_constant?(node.receiver)

    DEFINERS[node.receiver.name] == node.name
  end

  def self.core_constant?(node)
    return true if node.is_a?(Prism::ConstantReadNode)

    node.is_a?(Prism::ConstantPathNode) && node.parent.nil?
  end

  private_class_method :core_constant?
end
