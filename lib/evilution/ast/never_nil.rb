# frozen_string_literal: true

require "prism"
require_relative "../ast"

# Expressions whose value is never nil whatever the program does: `self` and
# the literals other than `nil`. Anything read or computed (a variable, a
# constant, a call) is not one.
module Evilution::AST::NeverNil
  NODE_TYPES = [
    Prism::SelfNode,
    Prism::StringNode,
    Prism::InterpolatedStringNode,
    Prism::XStringNode,
    Prism::InterpolatedXStringNode,
    Prism::SymbolNode,
    Prism::InterpolatedSymbolNode,
    Prism::IntegerNode,
    Prism::FloatNode,
    Prism::RationalNode,
    Prism::ImaginaryNode,
    Prism::ArrayNode,
    Prism::HashNode,
    Prism::RangeNode,
    Prism::RegularExpressionNode,
    Prism::InterpolatedRegularExpressionNode,
    Prism::TrueNode,
    Prism::FalseNode,
    Prism::LambdaNode
  ].freeze
  private_constant :NODE_TYPES

  def self.node?(node)
    NODE_TYPES.any? { |type| node.is_a?(type) }
  end
end
